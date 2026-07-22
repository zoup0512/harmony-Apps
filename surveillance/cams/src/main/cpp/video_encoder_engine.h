#pragma once

#include <string>
#include <atomic>
#include "napi/native_api.h"
#include "multimedia/player_framework/native_avcodec_videoencoder.h"
#include "multimedia/player_framework/native_avcodec_base.h"
#include "multimedia/player_framework/native_avbuffer.h"
#include "multimedia/player_framework/native_avformat.h"
#include "native_buffer/native_buffer.h"
#include "native_window/external_window.h"

struct EncoderCallbackData {
    uint8_t* data;
    int32_t size;
    int64_t pts;
    uint32_t flags;
};

class VideoEncoderEngine {
public:
    VideoEncoderEngine();
    ~VideoEncoderEngine();

    std::string create(int width, int height, int bitrate, int framerate);
    void start();
    void stop();
    void release();
    void setCallback(napi_env env, napi_value callback);

private:
    OH_AVCodec* encoder_ = nullptr;
    OHNativeWindow* nativeWindow_ = nullptr;
    uint64_t surfaceId_ = 0;
    napi_threadsafe_function tsfn_ = nullptr;
    napi_ref callbackRef_ = nullptr;
    std::atomic<bool> running_{false};

    static void onError(OH_AVCodec* codec, int32_t errorCode, void* userData);
    static void onStreamChanged(OH_AVCodec* codec, OH_AVFormat* format, void* userData);
    static void onNeedInputBuffer(OH_AVCodec* codec, uint32_t index, OH_AVBuffer* buffer, void* userData);
    static void onNewOutputBuffer(OH_AVCodec* codec, uint32_t index, OH_AVBuffer* buffer, void* userData);

    void handleOutputBuffer(uint32_t index, OH_AVBuffer* buffer);
    static void callJsCallback(napi_env env, napi_value jsCb, void* context, void* data);

};
