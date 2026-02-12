#include <ApplicationServices/ApplicationServices.h>
#include <stdio.h>

int main(void) {
  double kd = CGEventSourceSecondsSinceLastEventType(
      kCGEventSourceStateCombinedSessionState, kCGEventKeyDown);
  double ku = CGEventSourceSecondsSinceLastEventType(
      kCGEventSourceStateCombinedSessionState, kCGEventKeyUp);
  double idle = (kd < ku) ? kd : ku;
  printf("%d\n", (int)idle);
  return 0;
}
