#pragma once

#include <string>
#include <atomic>
#include <mutex>
#include <vector>
#include "napi/native_api.h"
#include "multimedia/player_framework/native_avcodec_audioencoder.h"
#include "multimedia/player_framework/native_avcodec_base.h"
#include "multimedia/player_framework/native_avbuffer.h"
#include "multimedia/player_framework/native_avformat.h"
#include "ohaudio/native_audiocapturer.h"
#include "ohaudio/native_audiostreambuilder.h"
#include "ohaudio/native_audio_common.h"

// One accumulated PCM chunk ready to feed the encoder (1024 samples/frame for AAC-LC)
struct PcmChunk {
    uint8_t* data;
    int32_t size;
    int64_t pts;
};

// Data passed through the threadsafe function to JS
struct AacCallbackData {
    uint8_t* data;
    int32_t size;
    int64_t pts;
    bool isConfig;
};

class AudioEncoderEngine {
public:
    AudioEncoderEngine();
    ~AudioEncoderEngine();

    // Returns "ok" on success, "" on failure
    std::string create(int sampleRate, int channelCount, int bitrate);
    void start();
    void stop();
    void release();
    void setCallback(napi_env env, napi_value callback);
    void setMuted(bool muted);

private:
    // Audio capturer (OHAudio)
    OH_AudioStreamBuilder* streamBuilder_ = nullptr;
    OH_AudioCapturer* capturer_ = nullptr;

    // Audio encoder (AVCodec)
    OH_AVCodec* encoder_ = nullptr;

    // PCM accumulation buffer (capturer writes, encoder reads)
    std::mutex pcmMutex_;
    std::vector<uint8_t> pcmAccum_;
    int64_t totalSamplesEncoded_ = 0; // samples-per-channel fed to encoder

    // Pending encoder input buffer (filled when PCM is available)
    std::mutex inputMutex_;
    int32_t pendingInputIndex_ = -1;

    int32_t sampleRate_ = 44100;
    int32_t channelCount_ = 2;
    int32_t frameBytes_ = 4096;  // 1024 samples * channels * 2 bytes

    std::atomic<bool> running_{false};
    std::atomic<bool> muted_{false};

    // JS callback (threadsafe)
    napi_threadsafe_function tsfn_ = nullptr;

    // --- Capturer callbacks (OHAudio) ---
    static int32_t onReadData(OH_AudioCapturer* capturer, void* userData,
                              void* buffer, int32_t bufferLen);

    // Feed one AAC frame's worth of PCM to the encoder if both buffer and data are ready.
    // Thread-safe; may be called from capturer or encoder threads.
    void tryFeedInput();

    // --- Encoder callbacks (AVCodec) ---
    static void onError(OH_AVCodec* codec, int32_t errorCode, void* userData);
    static void onStreamChanged(OH_AVCodec* codec, OH_AVFormat* format, void* userData);
    static void onNeedInputBuffer(OH_AVCodec* codec, uint32_t index, OH_AVBuffer* buffer, void* userData);
    static void onNewOutputBuffer(OH_AVCodec* codec, uint32_t index, OH_AVBuffer* buffer, void* userData);

    void handleOutputBuffer(uint32_t index, OH_AVBuffer* buffer);
    static void callJsCallback(napi_env env, napi_value jsCb, void* context, void* data);

    void clearPcmAccum();
};
