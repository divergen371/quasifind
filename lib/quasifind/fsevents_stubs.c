/* fsevents_stubs.c - macOS FSEvents integration for Quasifind */

#ifdef __APPLE__

#include <CoreServices/CoreServices.h>
#include <pthread.h>
#include <string.h>

#include <caml/mlvalues.h>
#include <caml/memory.h>
#include <caml/alloc.h>
#include <caml/fail.h>
#include <caml/callback.h>

/* Ring buffer for changed paths */
#define MAX_EVENTS 4096
#define MAX_PATH_LEN 1024

static struct
{
    char paths[MAX_EVENTS][MAX_PATH_LEN];
    int head;
    int tail;
    int count;
    pthread_mutex_t mutex;
} event_buf = {
    .head = 0,
    .tail = 0,
    .count = 0,
    .mutex = PTHREAD_MUTEX_INITIALIZER};

static FSEventStreamRef stream = NULL;
static pthread_t watch_thread;
static volatile int running = 0;

static void push_event(const char *path)
{
    pthread_mutex_lock(&event_buf.mutex);
    if (event_buf.count < MAX_EVENTS)
    {
        strncpy(event_buf.paths[event_buf.tail], path, MAX_PATH_LEN - 1);
        event_buf.paths[event_buf.tail][MAX_PATH_LEN - 1] = '\0';
        event_buf.tail = (event_buf.tail + 1) % MAX_EVENTS;
        event_buf.count++;
    }
    /* If full, silently drop (older events were already delivered) */
    pthread_mutex_unlock(&event_buf.mutex);
}

static void fsevents_callback(
    ConstFSEventStreamRef streamRef __attribute__((unused)),
    void *clientCallBackInfo __attribute__((unused)),
    size_t numEvents,
    void *eventPaths,
    const FSEventStreamEventFlags eventFlags[] __attribute__((unused)),
    const FSEventStreamEventId eventIds[] __attribute__((unused)))
{
    char **paths = (char **)eventPaths;
    for (size_t i = 0; i < numEvents; i++)
    {
        push_event(paths[i]);
    }
}

static void *runloop_thread(void *arg __attribute__((unused)))
{
    /* Use GCD dispatch queue instead of deprecated CFRunLoop approach */
    dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    FSEventStreamSetDispatchQueue(stream, queue);
    FSEventStreamStart(stream);

    /* Keep thread alive until stopped */
    while (running)
    {
        usleep(100000); /* 100ms */
    }
    return NULL;
}

CAMLprim value caml_fsevents_start(value v_path, value v_latency)
{
    CAMLparam2(v_path, v_latency);

    if (running)
    {
        CAMLreturn(Val_int(0)); /* Already running */
    }

    const char *path = String_val(v_path);
    double latency = Double_val(v_latency);

    CFStringRef cf_path = CFStringCreateWithCString(NULL, path, kCFStringEncodingUTF8);
    CFArrayRef paths_to_watch = CFArrayCreate(NULL, (const void **)&cf_path, 1, &kCFTypeArrayCallBacks);

    stream = FSEventStreamCreate(
        NULL,
        &fsevents_callback,
        NULL,
        paths_to_watch,
        kFSEventStreamEventIdSinceNow,
        latency,
        kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer);

    CFRelease(cf_path);
    CFRelease(paths_to_watch);

    if (!stream)
    {
        CAMLreturn(Val_int(-1));
    }

    running = 1;
    pthread_create(&watch_thread, NULL, runloop_thread, NULL);

    CAMLreturn(Val_int(1));
}

CAMLprim value caml_fsevents_poll(value v_unit)
{
    CAMLparam1(v_unit);
    CAMLlocal2(result, cons);

    result = Val_emptylist;

    pthread_mutex_lock(&event_buf.mutex);
    while (event_buf.count > 0)
    {
        /* Build list in reverse (most recent first, but that's fine) */
        cons = caml_alloc(2, 0);
        Store_field(cons, 0, caml_copy_string(event_buf.paths[event_buf.head]));
        Store_field(cons, 1, result);
        result = cons;

        event_buf.head = (event_buf.head + 1) % MAX_EVENTS;
        event_buf.count--;
    }
    pthread_mutex_unlock(&event_buf.mutex);

    CAMLreturn(result);
}

CAMLprim value caml_fsevents_stop(value v_unit)
{
    CAMLparam1(v_unit);

    if (running && stream)
    {
        running = 0;
        FSEventStreamStop(stream);
        FSEventStreamInvalidate(stream);
        FSEventStreamRelease(stream);
        stream = NULL;
        pthread_join(watch_thread, NULL);
    }

    CAMLreturn(Val_unit);
}

#else
/* Non-macOS: stub implementations that return "not available" */

#include <caml/mlvalues.h>
#include <caml/memory.h>

CAMLprim value caml_fsevents_start(value v_path, value v_latency)
{
    CAMLparam2(v_path, v_latency);
    (void)v_path;
    (void)v_latency;
    CAMLreturn(Val_int(-1)); /* Not available */
}

CAMLprim value caml_fsevents_poll(value v_unit)
{
    CAMLparam1(v_unit);
    CAMLreturn(Val_emptylist);
}

CAMLprim value caml_fsevents_stop(value v_unit)
{
    CAMLparam1(v_unit);
    CAMLreturn(Val_unit);
}

#endif
