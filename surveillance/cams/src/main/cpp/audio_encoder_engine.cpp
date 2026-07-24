#include "audio_encoder_engine.h"
#include "hilog/log.h"

#undef LOG_TAG
#undef LOG_DOMAIN
#define LOG_TAG "RtspEncoder"
#define LOG_DOMAIN 0x3200

#define LOGI(...) ((void)OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, __VA_ARGS__))
#define LOGE(...) ((void)OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, __VA_ARGS__))
#define LOGW(...) ((void)OH_LOG_Print(LOG_APP, LOG_WARN, LOG_DOMAIN, LOG_TAG, __VA_ARGS__))

// AAC-LC frame size is always 1024 samples per channel.
static constexpr int AAC_FRAME_SAMPLES = 1024;

AudioEncoderEngine::AudioEncoderEngine() {}

AudioEncoderEngine::~AudioEncoderEngine()
{
    release();
}

void AudioEncoderEngine::clearPcmAccum()
{
    std::lock_guard<std::mutex> lock(pcmMutex_);
    pcmAccum_.clear();
}

std::string AudioEncoderEngine::create(int sampleRate, int channelCount, int bitrate)
{
    sampleRate_ = sampleRate;
    channelCount_ = channelCount;
    frameBytes_ = AAC_FRAME_SAMPLES * channelCount_ * 2; // 16-bit PCM

    LOGI("AudioEncoder create BEGIN: sr=%d ch=%d bitrate=%d frameBytes=%d",
         sampleRate_, channelCount_, bitrate, frameBytes_);

    // ---- 1. Build the audio encoder (AAC-LC) ----
    encoder_ = OH_AudioEncoder_CreateByMime("audio/mp4a-latm");
    if (encoder_ == nullptr) {
        LOGE("Failed to create audio encoder");
        return "";
    }

    OH_AVFormat* format = OH_AVFormat_Create();
    OH_AVFormat_SetIntValue(format, OH_MD_KEY_AUD_SAMPLE_RATE, sampleRate_);
    OH_AVFormat_SetIntValue(format, OH_MD_KEY_AUD_CHANNEL_COUNT, channelCount_);
    OH_AVFormat_SetLongValue(format, OH_MD_KEY_BITRATE, (int64_t)bitrate);
    // 0 = AAC-LC profile
    OH_AVFormat_SetIntValue(format, OH_MD_KEY_AAC_IS_ADTS, 0);

    int32_t ret = OH_AudioEncoder_Configure(encoder_, format);
    OH_AVFormat_Destroy(format);
    if (ret != AV_ERR_OK) {
        LOGE("Failed to configure audio encoder: %{public}d", ret);
        OH_AudioEncoder_Destroy(encoder_);
        encoder_ = nullptr;
        return "";
    }

    OH_AVCodecAsyncCallback cb = {
        &AudioEncoderEngine::onError,
        &AudioEncoderEngine::onStreamChanged,
        &AudioEncoderEngine::onNeedInputBuffer,
        &AudioEncoderEngine::onNewOutputBuffer
    };
    ret = OH_AudioEncoder_RegisterCallback(encoder_, cb, this);
    if (ret != AV_ERR_OK) {
        LOGE("Failed to register audio encoder callback: %{public}d", ret);
        OH_AudioEncoder_Destroy(encoder_);
        encoder_ = nullptr;
        return "";
    }

    ret = OH_AudioEncoder_Prepare(encoder_);
    if (ret != AV_ERR_OK) {
        LOGE("Failed to prepare audio encoder: %{public}d", ret);
        OH_AudioEncoder_Destroy(encoder_);
        encoder_ = nullptr;
        return "";
    }
    LOGI("Audio encoder prepared");

    // ---- 2. Build the audio capturer (mic) ----
    OH_AudioStream_Type streamType = AUDIOSTREAM_TYPE_CAPTURER;
    ret = OH_AudioStreamBuilder_Create(&streamBuilder_, streamType);
    if (ret != AUDIOSTREAM_SUCCESS) {
        LOGE("Failed to create audio stream builder: %{public}d", ret);
        OH_AudioEncoder_Destroy(encoder_);
        encoder_ = nullptr;
        return "";
    }

    OH_AudioStreamBuilder_SetSamplingRate(streamBuilder_, sampleRate_);
    OH_AudioStreamBuilder_SetChannelLayout(streamBuilder_,
        channelCount_ == 2 ? CHANNEL_LAYOUT_STEREO : CHANNEL_LAYOUT_MONO);
    OH_AudioStreamBuilder_SetSampleFormat(streamBuilder_, AUDIOSTREAM_SAMPLE_S16LE);
    OH_AudioStreamBuilder_SetEncodingType(streamBuilder_, AUDIOSTREAM_ENCODING_TYPE_RAW);
    OH_AudioStreamBuilder_SetSourceType(streamBuilder_, AUDIOSTREAM_SOURCE_TYPE_MIC);
    OH_AudioCapturer_Callbacks callbacks;
    callbacks.OH_AudioCapturer_OnReadData = &AudioEncoderEngine::onReadData;
    callbacks.OH_AudioCapturer_OnStreamEvent = nullptr;
    callbacks.OH_AudioCapturer_OnInterruptEvent = nullptr;
    callbacks.OH_AudioCapturer_OnError = nullptr;
    ret = OH_AudioStreamBuilder_SetCapturerCallback(streamBuilder_, callbacks, this);
    if (ret != AUDIOSTREAM_SUCCESS) {
        LOGE("Failed to set capturer callback: %{public}d", ret);
        OH_AudioStreamBuilder_Destroy(streamBuilder_);
        streamBuilder_ = nullptr;
        OH_AudioEncoder_Destroy(encoder_);
        encoder_ = nullptr;
        return "";
    }
    // Keep latency low.
    OH_AudioStreamBuilder_SetLatencyMode(streamBuilder_, AUDIOSTREAM_LATENCY_MODE_FAST);

    ret = OH_AudioStreamBuilder_GenerateCapturer(streamBuilder_, &capturer_);
    if (ret != AUDIOSTREAM_SUCCESS) {
        LOGE("Failed to generate capturer: %{public}d", ret);
        OH_AudioStreamBuilder_Destroy(streamBuilder_);
        streamBuilder_ = nullptr;
        OH_AudioEncoder_Destroy(encoder_);
        encoder_ = nullptr;
        return "";
    }
    LOGI("Audio capturer generated");

    LOGI("AudioEncoder create END");
    return "ok";
}

void AudioEncoderEngine::start()
{
    if (encoder_ == nullptr || capturer_ == nullptr) return;

    int32_t ret = OH_AudioEncoder_Start(encoder_);
    if (ret != AV_ERR_OK) {
        LOGE("Failed to start audio encoder: %{public}d", ret);
        return;
    }

    ret = OH_AudioCapturer_Start(capturer_);
    if (ret != AUDIOSTREAM_SUCCESS) {
        LOGE("Failed to start capturer: %{public}d", ret);
        OH_AudioEncoder_Stop(encoder_);
        return;
    }

    running_ = true;
    LOGI("Audio encoder + capturer started");
}

void AudioEncoderEngine::stop()
{
    running_ = false;
    if (capturer_ != nullptr) {
        OH_AudioCapturer_Stop(capturer_);
    }
    if (encoder_ != nullptr) {
        OH_AudioEncoder_NotifyEndOfStream(encoder_);
        OH_AudioEncoder_Stop(encoder_);
    }
    clearPcmAccum();
    std::lock_guard<std::mutex> lock(inputMutex_);
    pendingInputIndex_ = -1;
    LOGI("Audio encoder + capturer stopped");
}

void AudioEncoderEngine::release()
{
    running_ = false;
    if (capturer_ != nullptr) {
        OH_AudioCapturer_Release(capturer_);
        capturer_ = nullptr;
    }
    if (streamBuilder_ != nullptr) {
        OH_AudioStreamBuilder_Destroy(streamBuilder_);
        streamBuilder_ = nullptr;
    }
    if (encoder_ != nullptr) {
        OH_AudioEncoder_Destroy(encoder_);
        encoder_ = nullptr;
    }
    clearPcmAccum();
    if (tsfn_ != nullptr) {
        napi_release_threadsafe_function(tsfn_, napi_tsfn_abort);
        tsfn_ = nullptr;
    }
    totalSamplesEncoded_ = 0;
    LOGI("Audio encoder released");
}

void AudioEncoderEngine::setMuted(bool muted)
{
    muted_ = muted;
    // When muting, drop any accumulated PCM so we don't leak stale audio on resume.
    if (muted) {
        clearPcmAccum();
    }
    LOGI("Audio muted=%{public}d", muted ? 1 : 0);
}

void AudioEncoderEngine::setCallback(napi_env env, napi_value callback)
{
    napi_value resourceName;
    napi_create_string_utf8(env, "AudioEncoderCallback", NAPI_AUTO_LENGTH, &resourceName);

    napi_create_threadsafe_function(env, callback, nullptr, resourceName,
        0, 1, nullptr, nullptr, this,
        &AudioEncoderEngine::callJsCallback, &tsfn_);
}

// ---- Capturer: mic data arrives on the audio thread ----
int32_t AudioEncoderEngine::onReadData(OH_AudioCapturer* capturer, void* userData,
                                       void* buffer, int32_t bufferLen)
{
    auto* self = static_cast<AudioEncoderEngine*>(userData);
    if (self == nullptr || !self->running_) return 0;

    // Hot mute: keep draining the mic (so the capture pipeline stays alive and pts
    // advances), but discard the samples so nothing reaches the encoder.
    if (self->muted_.load()) {
        return 0;
    }

    if (buffer == nullptr || bufferLen <= 0) return 0;

    {
        std::lock_guard<std::mutex> lock(self->pcmMutex_);
        const uint8_t* src = static_cast<const uint8_t*>(buffer);
        self->pcmAccum_.insert(self->pcmAccum_.end(), src, src + bufferLen);
    }

    self->tryFeedInput();
    return 0;
}

// ---- Encoder: framework asks for input ----
void AudioEncoderEngine::onNeedInputBuffer(OH_AVCodec* codec, uint32_t index, OH_AVBuffer* buffer, void* userData)
{
    auto* self = static_cast<AudioEncoderEngine*>(userData);
    if (self == nullptr) {
        OH_AudioEncoder_PushInputBuffer(codec, index);
        return;
    }
    // Remember the input slot; actual feeding happens when PCM is available.
    {
        std::lock_guard<std::mutex> lock(self->inputMutex_);
        self->pendingInputIndex_ = static_cast<int32_t>(index);
    }
    self->tryFeedInput();
}

// Pumps one AAC frame into the encoder when both a pending input slot and enough
// PCM are available. Thread-safe; may be called from the capturer or encoder thread.
void AudioEncoderEngine::tryFeedInput()
{
    if (encoder_ == nullptr) return;

    uint32_t index;
    {
        std::lock_guard<std::mutex> inLock(inputMutex_);
        if (pendingInputIndex_ < 0) return;
        index = static_cast<uint32_t>(pendingInputIndex_);
    }

    OH_AVBuffer* buffer = nullptr;
    int32_t ret = OH_AudioEncoder_GetInputBuffer(encoder_, index, &buffer);
    if (ret != AV_ERR_OK || buffer == nullptr) {
        LOGW("tryFeedInput: GetInputBuffer failed: %{public}d", ret);
        return;
    }
    uint8_t* dst = OH_AVBuffer_GetAddr(buffer);
    if (dst == nullptr) return;

    {
        std::lock_guard<std::mutex> pcmLock(pcmMutex_);
        if (static_cast<int32_t>(pcmAccum_.size()) < frameBytes_) {
            return; // not enough PCM yet
        }
        memcpy(dst, pcmAccum_.data(), frameBytes_);
        pcmAccum_.erase(pcmAccum_.begin(), pcmAccum_.begin() + frameBytes_);

        OH_AVCodecBufferAttr attr;
        attr.size = frameBytes_;
        attr.offset = 0;
        attr.pts = (static_cast<int64_t>(totalSamplesEncoded_) * 1000000) / sampleRate_; // microseconds
        attr.flags = AVCODEC_BUFFER_FLAGS_NONE;
        totalSamplesEncoded_ += AAC_FRAME_SAMPLES;
        OH_AVBuffer_SetBufferAttr(buffer, &attr);
    }

    ret = OH_AudioEncoder_PushInputBuffer(encoder_, index);
    if (ret != AV_ERR_OK) {
        LOGE("tryFeedInput: PushInputBuffer failed: %{public}d", ret);
    }

    {
        std::lock_guard<std::mutex> inLock(inputMutex_);
        if (pendingInputIndex_ == static_cast<int32_t>(index)) {
            pendingInputIndex_ = -1;
        }
    }
}

void AudioEncoderEngine::onStreamChanged(OH_AVCodec* codec, OH_AVFormat* format, void* userData)
{
    LOGI("Audio encoder stream changed");
}

void AudioEncoderEngine::onError(OH_AVCodec* codec, int32_t errorCode, void* userData)
{
    LOGE("Audio encoder error: %{public}d", errorCode);
}

void AudioEncoderEngine::onNewOutputBuffer(OH_AVCodec* codec, uint32_t index, OH_AVBuffer* buffer, void* userData)
{
    auto* self = static_cast<AudioEncoderEngine*>(userData);
    if (self == nullptr || !self->running_) {
        OH_AudioEncoder_FreeOutputBuffer(codec, index);
        return;
    }
    self->handleOutputBuffer(index, buffer);
}

void AudioEncoderEngine::handleOutputBuffer(uint32_t index, OH_AVBuffer* buffer)
{
    OH_AVCodecBufferAttr attr;
    int32_t ret = OH_AVBuffer_GetBufferAttr(buffer, &attr);
    if (ret != AV_ERR_OK) {
        LOGE("handleOutputBuffer: GetBufferAttr failed: %{public}d", ret);
        OH_AudioEncoder_FreeOutputBuffer(encoder_, index);
        return;
    }

    uint8_t* addr = OH_AVBuffer_GetAddr(buffer);
    if (addr == nullptr || attr.size <= 0) {
        OH_AudioEncoder_FreeOutputBuffer(encoder_, index);
        return;
    }

    // The first output carrying CODEC_DATA is the AudioSpecificConfig (2 bytes for AAC-LC).
    bool isConfig = (attr.flags & AVCODEC_BUFFER_FLAGS_CODEC_DATA) != 0;

    static int outCount = 0;
    if (outCount < 3 || (outCount % 50) == 0) {
        LOGI("Audio out: count=%{public}d size=%{public}d pts=%{public}lld isConfig=%{public}d",
             outCount, attr.size, (long long)attr.pts, isConfig ? 1 : 0);
    }
    outCount++;

    if (tsfn_ != nullptr) {
        auto* cbData = new AacCallbackData();
        cbData->data = new uint8_t[attr.size];
        memcpy(cbData->data, addr, attr.size);
        cbData->size = attr.size;
        cbData->pts = attr.pts;
        cbData->isConfig = isConfig;

        napi_call_threadsafe_function(tsfn_, cbData, napi_tsfn_nonblocking);
    }

    OH_AudioEncoder_FreeOutputBuffer(encoder_, index);
}

void AudioEncoderEngine::callJsCallback(napi_env env, napi_value jsCb, void* context, void* data)
{
    auto* cbData = static_cast<AacCallbackData*>(data);
    if (cbData == nullptr) return;

    napi_value undefined;
    napi_get_undefined(env, &undefined);

    napi_value arrayBuffer;
    void* outBuffer = nullptr;
    napi_create_arraybuffer(env, cbData->size, &outBuffer, &arrayBuffer);
    memcpy(outBuffer, cbData->data, cbData->size);

    napi_value obj;
    napi_create_object(env, &obj);
    napi_set_named_property(env, obj, "data", arrayBuffer);

    napi_value ptsVal;
    napi_create_int64(env, cbData->pts, &ptsVal);
    napi_set_named_property(env, obj, "pts", ptsVal);

    napi_value isConfigVal;
    napi_get_boolean(env, cbData->isConfig, &isConfigVal);
    napi_set_named_property(env, obj, "isConfig", isConfigVal);

    napi_call_function(env, undefined, jsCb, 1, &obj, nullptr);

    delete[] cbData->data;
    delete cbData;
}
