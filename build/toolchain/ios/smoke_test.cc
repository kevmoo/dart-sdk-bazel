#include <CoreFoundation/CoreFoundation.h>
#include <TargetConditionals.h>

#if !TARGET_OS_IPHONE
#error "Expected TARGET_OS_IPHONE to be defined and true"
#endif

int ios_smoke_test_function() {
  CFStringRef str = CFSTR("iOS Smoke Test");
  return str != nullptr ? 0 : 1;
}
