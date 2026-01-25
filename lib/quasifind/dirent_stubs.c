/* dirent_stubs.c - Expose readdir with d_type for OCaml */

#include <sys/types.h>
#include <dirent.h>
#include <string.h>
#include <stdio.h>
#include <errno.h>

#include <caml/mlvalues.h>
#include <caml/memory.h>
#include <caml/alloc.h>
#include <caml/fail.h>
#include <caml/unixsupport.h>

/*
   We map d_type to a simple OCaml variant or int.
   Let's use int for simplicity in C, and map to variant in OCaml.

   Unknown = 0
   Reg = 1
   Dir = 2
   Symlink = 3
   Other = 4
*/

static int map_dtype(unsigned char type)
{
#ifdef DT_REG
    if (type == DT_REG)
        return 1;
#endif
#ifdef DT_DIR
    if (type == DT_DIR)
        return 2;
#endif
#ifdef DT_LNK
    if (type == DT_LNK)
        return 3;
#endif
    /* Treat everything else or unknown as 0 (Unknown/Other), requiring stat */
    return 0;
}

CAMLprim value caml_readdir_with_type(value v_path)
{
    CAMLparam1(v_path);
    CAMLlocal3(v_entries, v_entry, v_name);

    const char *path = String_val(v_path);
    DIR *d = opendir(path);

    if (d == NULL)
    {
        uerror("opendir", v_path);
    }

    struct dirent *de;
    /* We'll use a linked list of entries first since we don't know count */
    /* Actually, for performance, we can allocate a list directly in OCaml heap?
       Or easier: just return array. We need to iterate twice or resize.
       Let's use OCaml standard List construction to avoid complex C memory management.
    */

    v_entries = Val_int(0); /* Empty list [] */

    /* We need to handle potential errors during readdir, but typically it just returns NULL at end */
    errno = 0;
    while ((de = readdir(d)) != NULL)
    {
        /* Skip . and .. */
        if (strcmp(de->d_name, ".") == 0 || strcmp(de->d_name, "..") == 0)
        {
            continue;
        }

        v_name = caml_copy_string(de->d_name);
        int kind = map_dtype(de->d_type);

        /* create tuple (name, kind) */
        v_entry = caml_alloc_tuple(2);
        Store_field(v_entry, 0, v_name);
        Store_field(v_entry, 1, Val_int(kind));

        /* cons to list: v_entries = v_entry :: v_entries */
        value desc = caml_alloc_tuple(2);
        Store_field(desc, 0, v_entry);
        Store_field(desc, 1, v_entries);
        v_entries = desc;
    }

    if (errno != 0)
    {
        /* Verify error */
        /* But we already have some entries? POSIX says readdir returns NULL on end or error.
           If error, errno is set. */
        /* We usually ignore errors during readdir in find utils, or warn.
           uerror would raise exception. Let's close and raise. */
        int saved_errno = errno;
        closedir(d);
        unix_error(saved_errno, "readdir", v_path);
    }

    closedir(d);

    CAMLreturn(v_entries);
}
