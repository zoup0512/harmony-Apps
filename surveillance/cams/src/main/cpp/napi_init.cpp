#include "napi/native_api.h"
#include "video_encoder_engine.h"
#include "audio_encoder_engine.h"
#include "hilog/log.h"

#undef LOG_TAG
#undef LOG_DOMAIN
#define LOG_TAG "RtspEncoder"
#define LOG_DOMAIN 0x3200

#define LOGI(...) ((void)OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, __VA_ARGS__))

static VideoEncoderEngine* g_encoder = nullptr;
static AudioEncoderEngine* g_audioEncoder = nullptr;

static napi_value CreateEncoder(napi_env env, napi_callback_info info)
{
    size_t argc = 5;
    napi_value args[5];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    int width, height, bitrate, framerate;
    napi_get_value_int32(env, args[0], &width);
    napi_get_value_int32(env, args[1], &height);
    napi_get_value_int32(env, args[2], &bitrate);
    napi_get_value_int32(env, args[3], &framerate);

    if (g_encoder != nullptr) {
        delete g_encoder;
        g_encoder = nullptr;
    }

    g_encoder = new VideoEncoderEngine();
    std::string surfaceId = g_encoder->create(width, height, bitrate, framerate);

    // Set callback (args[4])
    napi_value callback = args[4];
    g_encoder->setCallback(env, callback);

    napi_value result;
    napi_create_string_utf8(env, surfaceId.c_str(), NAPI_AUTO_LENGTH, &result);
    return result;
}

static napi_value StartEncoder(napi_env env, napi_callback_info info)
{
    if (g_encoder != nullptr) {
        g_encoder->start();
    }
    napi_value undefined;
    napi_get_undefined(env, &undefined);
    return undefined;
}

static napi_value StopEncoder(napi_env env, napi_callback_info info)
{
    if (g_encoder != nullptr) {
        g_encoder->stop();
    }
    napi_value undefined;
    napi_get_undefined(env, &undefined);
    return undefined;
}

static napi_value ReleaseEncoder(napi_env env, napi_callback_info info)
{
    if (g_encoder != nullptr) {
        g_encoder->release();
        delete g_encoder;
        g_encoder = nullptr;
    }
    napi_value undefined;
    napi_get_undefined(env, &undefined);
    return undefined;
}

static napi_value CreateAudioEncoder(napi_env env, napi_callback_info info)
{
    size_t argc = 4;
    napi_value args[4];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    int sampleRate, channelCount, bitrate;
    napi_get_value_int32(env, args[0], &sampleRate);
    napi_get_value_int32(env, args[1], &channelCount);
    napi_get_value_int32(env, args[2], &bitrate);

    if (g_audioEncoder != nullptr) {
        delete g_audioEncoder;
        g_audioEncoder = nullptr;
    }

    g_audioEncoder = new AudioEncoderEngine();
    std::string result = g_audioEncoder->create(sampleRate, channelCount, bitrate);

    napi_value callback = args[3];
    g_audioEncoder->setCallback(env, callback);

    napi_value ret;
    napi_create_string_utf8(env, result.c_str(), NAPI_AUTO_LENGTH, &ret);
    return ret;
}

static napi_value StartAudioEncoder(napi_env env, napi_callback_info info)
{
    if (g_audioEncoder != nullptr) {
        g_audioEncoder->start();
    }
    napi_value undefined;
    napi_get_undefined(env, &undefined);
    return undefined;
}

static napi_value StopAudioEncoder(napi_env env, napi_callback_info info)
{
    if (g_audioEncoder != nullptr) {
        g_audioEncoder->stop();
    }
    napi_value undefined;
    napi_get_undefined(env, &undefined);
    return undefined;
}

static napi_value ReleaseAudioEncoder(napi_env env, napi_callback_info info)
{
    if (g_audioEncoder != nullptr) {
        g_audioEncoder->release();
        delete g_audioEncoder;
        g_audioEncoder = nullptr;
    }
    napi_value undefined;
    napi_get_undefined(env, &undefined);
    return undefined;
}

static napi_value SetAudioEncoderMuted(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value args[1];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    bool muted = false;
    napi_get_value_bool(env, args[0], &muted);

    if (g_audioEncoder != nullptr) {
        g_audioEncoder->setMuted(muted);
    }
    napi_value undefined;
    napi_get_undefined(env, &undefined);
    return undefined;
}

EXTERN_C_START
static napi_value Init(napi_env env, napi_value exports)
{
    napi_property_descriptor desc[] = {
        { "createEncoder", nullptr, CreateEncoder, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "startEncoder", nullptr, StartEncoder, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "stopEncoder", nullptr, StopEncoder, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "releaseEncoder", nullptr, ReleaseEncoder, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "createAudioEncoder", nullptr, CreateAudioEncoder, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "startAudioEncoder", nullptr, StartAudioEncoder, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "stopAudioEncoder", nullptr, StopAudioEncoder, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "releaseAudioEncoder", nullptr, ReleaseAudioEncoder, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "setAudioEncoderMuted", nullptr, SetAudioEncoderMuted, nullptr, nullptr, nullptr, napi_default, nullptr },
    };
    napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);
    return exports;
}
EXTERN_C_END

static napi_module demoModule = {
    .nm_version = 1,
    .nm_flags = 0,
    .nm_filename = nullptr,
    .nm_register_func = Init,
    .nm_modname = "rtspencoder",
    .nm_priv = ((void *)0),
    .reserved = { 0 },
};

extern "C" __attribute__((constructor)) void RegisterModule(void)
{
    napi_module_register(&demoModule);
}
