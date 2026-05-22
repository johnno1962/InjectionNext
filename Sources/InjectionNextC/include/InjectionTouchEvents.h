//
//  InjectionTouchEvents.h
//  InjectionNext
//
//  Lightweight touch capture/replay hooks for MCP event macros.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^InjectionTouchEventCallback)(const char *_Nonnull json);

#ifdef __cplusplus
extern "C" {
#endif

void InjectionInstallTouchEventCapture(InjectionTouchEventCallback _Nonnull callback);
void InjectionReplayTouchEventsJSON(const char *_Nonnull json);

#ifdef __cplusplus
}
#endif

NS_ASSUME_NONNULL_END
