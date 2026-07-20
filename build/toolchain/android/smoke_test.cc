#include <android/log.h>

void smoke_test_android() {
    __android_log_print(ANDROID_LOG_INFO, "DartSDK", "Android C++ toolchain smoke test OK");
}
