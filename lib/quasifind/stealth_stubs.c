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
CAMLprim value caml_set_process_name(value v_name)
{
    CAMLparam1(v_name);
    const char *name = String_val(v_name);

#ifdef __linux__
    /* Linux: use prctl to set process name */
    prctl(PR_SET_NAME, name, 0, 0, 0);
#endif

#ifdef __APPLE__
    /* macOS: use pthread_setname_np so it shows up in activity monitor/crash logs */
    pthread_setname_np(name);

/* ALSO try to overwrite argv[0] to fool ps */
/* This requires access to the raw argv memory via _NSGetArgv */
#include <crt_externs.h>
    char ***ns_argv = _NSGetArgv();
    char **argv = *ns_argv;

    if (argv && argv[0])
    {
        /* Aggressive strategy: Find the total contiguous length of argv strings to maximize space. */
        char *start = argv[0];
        char *end = argv[0] + strlen(argv[0]);

        /* Find the end of the last contiguous argument */
        for (int i = 1; argv[i] != NULL; i++)
        {
            size_t len = strlen(argv[i]);
            /* Check continuity: current arg should start right after previous arg's null terminator */
            if (argv[i] == end + 1)
            {
                end = argv[i] + len;
            }
            else
            {
                /* Discontinuity found, stop strict contiguous grouping here */
                break;
            }
        }

        /* Wipe the contiguous block */
        size_t total_contiguous_len = end - start;
        memset(start, 0, total_contiguous_len);

        /* Write fake name into the contiguous block */
        size_t name_len = strlen(name);
        if (name_len > total_contiguous_len)
            name_len = total_contiguous_len;
        memcpy(start, name, name_len);

        /* IMPORTANT: Wipe ALL remaining arguments independently */
        for (int i = 1; argv[i] != NULL; i++)
        {
            char *arg_ptr = argv[i];
            /* If this arg overlaps with the new name (in the contiguous block),
               skip the overlapping part to avoid overwriting the name we just wrote. */
            if (arg_ptr < start + name_len)
            {
                size_t arg_len = strlen(arg_ptr); /* Note: strlen might be 0 if we just memset it effectively, but let's be safe */
                char *arg_end = arg_ptr + arg_len;
                char *name_end = start + name_len;

                if (name_end < arg_end)
                {
                    /* Zeros out the tail of this arg that is NOT part of the new name */
                    memset(name_end, 0, arg_end - name_end);
                }
                continue;
            }

            /* Safe to wipe completely */
            memset(arg_ptr, 0, strlen(arg_ptr));
        }

        /* Nullify argv[1] to update the pointer array as well */
        if (argv[1] != NULL)
            argv[1] = NULL;
    }
#endif

    CAMLreturn(Val_unit);
}
