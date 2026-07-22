#include "video_encoder_engine.h"
#include "hilog/log.h"
#include <sys/time.h>

#undef LOG_TAG
#undef LOG_DOMAIN
#define LOG_TAG "RtspEncoder"
#define LOG_DOMAIN 0x3200

#define LOGI(...) ((void)OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, __VA_ARGS__))
#define LOGE(...) ((void)OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, __VA_ARGS__))
#define LOGW(...) ((void)OH_LOG_Print(LOG_APP, LOG_WARN, LOG_DOMAIN, LOG_TAG, __VA_ARGS__))

static int64_t GetNowMs()
{
    struct timeval tv;
    gettimeofday(&tv, nullptr);
    return (int64_t)tv.tv_sec * 1000 + tv.tv_usec / 1000;
}

VideoEncoderEngine::VideoEncoderEngine() {}

VideoEncoderEngine::~VideoEncoderEngine()
{
    release();
}

std::string VideoEncoderEngine::create(int width, int height, int bitrate, int framerate)
{
    LOGI("create BEGIN: %dx%d bitrate=%d fps=%d", width, height, bitrate, framerate);
    encoder_ = OH_VideoEncoder_CreateByMime("video/avc");
    if (encoder_ == nullptr) {
        LOGE("Failed to create video encoder");
        return "";
    }
    LOGI("Encoder created by mime");

    OH_AVFormat* format = OH_AVFormat_Create();
    OH_AVFormat_SetIntValue(format, OH_MD_KEY_WIDTH, width);
    OH_AVFormat_SetIntValue(format, OH_MD_KEY_HEIGHT, height);
    OH_AVFormat_SetIntValue(format, OH_MD_KEY_PIXEL_FORMAT, AV_PIXEL_FORMAT_SURFACE_FORMAT);
    OH_AVFormat_SetLongValue(format, OH_MD_KEY_BITRATE, (int64_t)bitrate);
    OH_AVFormat_SetDoubleValue(format, OH_MD_KEY_FRAME_RATE, (double)framerate);
    OH_AVFormat_SetIntValue(format, OH_MD_KEY_VIDEO_ENCODE_BITRATE_MODE, BITRATE_MODE_VBR);

    int32_t ret = OH_VideoEncoder_Configure(encoder_, format);
    OH_AVFormat_Destroy(format);
    if (ret != AV_ERR_OK) {
        LOGE("Failed to configure encoder: %{public}d", ret);
        OH_VideoEncoder_Destroy(encoder_);
        encoder_ = nullptr;
        return "";
    }
    LOGI("Encoder configured");

    OH_AVCodecCallback cb = {
        &VideoEncoderEngine::onError,
        &VideoEncoderEngine::onStreamChanged,
        &VideoEncoderEngine::onNeedInputBuffer,
        &VideoEncoderEngine::onNewOutputBuffer
    };
    ret = OH_VideoEncoder_RegisterCallback(encoder_, cb, this);
    if (ret != AV_ERR_OK) {
        LOGE("Failed to register callback: %{public}d", ret);
        OH_VideoEncoder_Destroy(encoder_);
        encoder_ = nullptr;
        return "";
    }
    LOGI("Encoder callback registered");

    ret = OH_VideoEncoder_Prepare(encoder_);
    if (ret != AV_ERR_OK) {
        LOGE("Failed to prepare encoder: %{public}d", ret);
        OH_VideoEncoder_Destroy(encoder_);
        encoder_ = nullptr;
        return "";
    }
    LOGI("Encoder prepared");

    ret = OH_VideoEncoder_GetSurface(encoder_, &nativeWindow_);
    if (ret != AV_ERR_OK || nativeWindow_ == nullptr) {
        LOGE("Failed to get surface from encoder: %{public}d", ret);
        OH_VideoEncoder_Destroy(encoder_);
        encoder_ = nullptr;
        return "";
    }
    LOGI("Encoder surface obtained");

    ret = OH_NativeWindow_GetSurfaceId(nativeWindow_, &surfaceId_);
    if (ret != 0) {
        LOGE("Failed to get surface id: %{public}d", ret);
        OH_VideoEncoder_Destroy(encoder_);
        encoder_ = nullptr;
        return "";
    }

    LOGI("create END: surfaceId=%{public}llu", (unsigned long long)surfaceId_);
    return std::to_string(surfaceId_);
}

void VideoEncoderEngine::start()
{
    if (encoder_ == nullptr) return;
    int32_t ret = OH_VideoEncoder_Start(encoder_);
    if (ret != AV_ERR_OK) {
        LOGE("Failed to start encoder: %{public}d", ret);
    } else {
        running_ = true;
        LOGI("Encoder started");
    }
}

void VideoEncoderEngine::stop()
{
    running_ = false;
    if (encoder_ == nullptr) return;
    OH_VideoEncoder_NotifyEndOfStream(encoder_);
    OH_VideoEncoder_Stop(encoder_);
    LOGI("Encoder stopped");
}

void VideoEncoderEngine::release()
{
    running_ = false;
    if (encoder_ != nullptr) {
        OH_VideoEncoder_Destroy(encoder_);
        encoder_ = nullptr;
    }
    nativeWindow_ = nullptr;
    surfaceId_ = 0;
    if (tsfn_ != nullptr) {
        napi_release_threadsafe_function(tsfn_, napi_tsfn_abort);
        tsfn_ = nullptr;
    }
    LOGI("Encoder released");
}

void VideoEncoderEngine::setCallback(napi_env env, napi_value callback)
{
    napi_value resourceName;
    napi_create_string_utf8(env, "VideoEncoderCallback", NAPI_AUTO_LENGTH, &resourceName);

    napi_create_threadsafe_function(env, callback, nullptr, resourceName,
        0, 1, nullptr, nullptr, this,
        &VideoEncoderEngine::callJsCallback, &tsfn_);
}

void VideoEncoderEngine::onError(OH_AVCodec* codec, int32_t errorCode, void* userData)
{
    LOGE("Encoder error: %{public}d", errorCode);
}

void VideoEncoderEngine::onStreamChanged(OH_AVCodec* codec, OH_AVFormat* format, void* userData)
{
    LOGI("Encoder stream changed");
}

void VideoEncoderEngine::onNeedInputBuffer(OH_AVCodec* codec, uint32_t index, OH_AVBuffer* buffer, void* userData)
{
    // Surface mode - no action needed, but log first few
    static int inputCount = 0;
    if (inputCount < 3) {
        LOGI("onNeedInputBuffer: index=%{public}u (count=%{public}d)", index, inputCount);
        inputCount++;
    }
}

void VideoEncoderEngine::onNewOutputBuffer(OH_AVCodec* codec, uint32_t index, OH_AVBuffer* buffer, void* userData)
{
    auto* self = static_cast<VideoEncoderEngine*>(userData);
    if (self == nullptr || !self->running_) {
        OH_VideoEncoder_FreeOutputBuffer(codec, index);
        return;
    }
    self->handleOutputBuffer(index, buffer);
}

void VideoEncoderEngine::handleOutputBuffer(uint32_t index, OH_AVBuffer* buffer)
{
    OH_AVCodecBufferAttr attr;
    int32_t ret = OH_AVBuffer_GetBufferAttr(buffer, &attr);
    if (ret != AV_ERR_OK) {
        LOGE("handleOutputBuffer: GetBufferAttr failed: %{public}d", ret);
        OH_VideoEncoder_FreeOutputBuffer(encoder_, index);
        return;
    }

    uint8_t* addr = OH_AVBuffer_GetAddr(buffer);
    if (addr == nullptr || attr.size <= 0) {
        LOGE("handleOutputBuffer: addr is null or size<=0: size=%{public}d", attr.size);
        OH_VideoEncoder_FreeOutputBuffer(encoder_, index);
        return;
    }

    static int outputCount = 0;
    if (outputCount < 5 || (outputCount % 30) == 0) {
        LOGI("handleOutputBuffer: count=%{public}d, size=%{public}d, pts=%{public}lld, flags=%{public}u", outputCount, attr.size, (long long)attr.pts, attr.flags);
    }
    outputCount++;

    // Extract SPS/PPS from the format metadata if available
    if (attr.flags & AVCODEC_BUFFER_FLAGS_CODEC_DATA) {
        LOGI("handleOutputBuffer: received codec data (SPS/PPS), size=%{public}d", attr.size);
    }

    // Copy data and send to JS callback
    if (tsfn_ != nullptr) {
        auto* cbData = new EncoderCallbackData();
        cbData->data = new uint8_t[attr.size];
        memcpy(cbData->data, addr, attr.size);
        cbData->size = attr.size;
        cbData->pts = attr.pts;
        cbData->flags = attr.flags;

        napi_call_threadsafe_function(tsfn_, cbData, napi_tsfn_nonblocking);
    } else {
        LOGE("handleOutputBuffer: tsfn_ is null, cannot send callback");
    }

    OH_VideoEncoder_FreeOutputBuffer(encoder_, index);
}

// Thread-safe function to call JS callback
void VideoEncoderEngine::callJsCallback(napi_env env, napi_value jsCb, void* context, void* data)
{
    auto* cbData = static_cast<EncoderCallbackData*>(data);
    if (cbData == nullptr) return;

    napi_value callback = jsCb;
    napi_value undefined;
    napi_get_undefined(env, &undefined);

    // Create ArrayBuffer from data
    napi_value arrayBuffer;
    void* outBuffer = nullptr;
    napi_create_arraybuffer(env, cbData->size, &outBuffer, &arrayBuffer);
    memcpy(outBuffer, cbData->data, cbData->size);

    // Create object with data, pts, flags, isKeyFrame
    napi_value obj;
    napi_create_object(env, &obj);
    napi_set_named_property(env, obj, "data", arrayBuffer);

    napi_value ptsVal;
    napi_create_int64(env, cbData->pts, &ptsVal);
    napi_set_named_property(env, obj, "pts", ptsVal);

    napi_value flagsVal;
    napi_create_uint32(env, cbData->flags, &flagsVal);
    napi_set_named_property(env, obj, "flags", flagsVal);

    napi_value isKeyFrame;
    napi_get_boolean(env, (cbData->flags & AVCODEC_BUFFER_FLAGS_SYNC_FRAME) != 0 || (cbData->flags & AVCODEC_BUFFER_FLAGS_CODEC_DATA) != 0, &isKeyFrame);
    napi_set_named_property(env, obj, "isKeyFrame", isKeyFrame);

    napi_call_function(env, undefined, callback, 1, &obj, nullptr);

    delete[] cbData->data;
    delete cbData;
}
