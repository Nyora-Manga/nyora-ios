// NyoraNativeBridge.h
//
// C ABI for the GraalVM native-image parser engine (libnyoraengine).
//
// The native-image build ALSO generates its own `libnyoraengine.h`; this hand-authored
// header declares the exact subset the Swift side calls so Nyora.xcodeproj can compile
// against it (add this file to the app's bridging header). The two must stay consistent
// with the @CEntryPoint signatures in NyoraNativeEntry.kt.

#ifndef NYORA_NATIVE_BRIDGE_H
#define NYORA_NATIVE_BRIDGE_H

#include <stddef.h>

// GraalVM isolate handles (opaque). native-image exports graal_create_isolate /
// graal_attach_thread / graal_detach_thread / graal_tear_down_isolate for every image.
typedef struct __graal_isolate_t graal_isolate_t;
typedef struct __graal_isolatethread_t graal_isolatethread_t;

#ifdef __cplusplus
extern "C" {
#endif

int graal_create_isolate(void* params, graal_isolate_t** isolate, graal_isolatethread_t** thread);
int graal_attach_thread(graal_isolate_t* isolate, graal_isolatethread_t** thread);
int graal_detach_thread(graal_isolatethread_t* thread);
int graal_tear_down_isolate(graal_isolatethread_t* thread);

// The URLSession transport callback Swift registers. Invoked (possibly concurrently)
// from the engine's OkHttp worker threads. Receives a malloc'd request-JSON C string it
// must NOT free (the engine frees it); returns a malloc'd response-JSON C string the
// engine frees. See NyoraNativeEntry.registerHttp / NativeHttpTransport.
typedef char* (*nyora_http_callback_t)(graal_isolatethread_t* thread, char* request_json);

void  nyora_register_http(graal_isolatethread_t* thread, nyora_http_callback_t callback);
char* nyora_request(graal_isolatethread_t* thread, char* path, char* params_json);
void  nyora_free(graal_isolatethread_t* thread, char* ptr);

#ifdef __cplusplus
}
#endif

#endif // NYORA_NATIVE_BRIDGE_H
