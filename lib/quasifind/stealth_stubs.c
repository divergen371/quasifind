#include <string.h>
#include <caml/mlvalues.h>
#include <caml/memory.h>
#include <caml/alloc.h>

#ifdef __linux__
#include <sys/prctl.h>
#endif

#ifdef __APPLE__
#include <pthread.h>
#endif

/* Set process name to hide from ps/top */
CAMLprim value caml_set_process_name(value v_name) {
    CAMLparam1(v_name);
    const char *name = String_val(v_name);
    
#ifdef __linux__
    /* Linux: use prctl to set process name */
    prctl(PR_SET_NAME, name, 0, 0, 0);
#endif

#ifdef __APPLE__
    /* macOS: use pthread_setname_np */
    pthread_setname_np(name);
#endif

    CAMLreturn(Val_unit);
}
