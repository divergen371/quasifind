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
#include <caml/custom.h>

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

/* --- Batch Readdir Implementation --- */

/* Custom block for DIR* to handle finalization safely */
static struct custom_operations dir_handle_ops = {
    "quasifind.dir_handle",
    custom_finalize_default,
    custom_compare_default,
    custom_hash_default,
    custom_serialize_default,
    custom_deserialize_default,
    custom_compare_ext_default,
    custom_fixed_length_default};

/* Access hidden struct safely */
#define Dir_val(v) (*((DIR **)Data_custom_val(v)))

CAMLprim value caml_opendir(value v_path)
{
    CAMLparam1(v_path);
    const char *path = String_val(v_path);

    DIR *d = opendir(path);
    if (d == NULL)
    {
        uerror("opendir", v_path);
    }

    value v_dir = caml_alloc_custom(&dir_handle_ops, sizeof(DIR *), 0, 1);
    Dir_val(v_dir) = d;

    CAMLreturn(v_dir);
}

CAMLprim value caml_closedir(value v_dir)
{
    CAMLparam1(v_dir);
    DIR *d = Dir_val(v_dir);
    if (d != NULL)
    {
        closedir(d);
        Dir_val(v_dir) = NULL; /* Prevent double close */
    }
    CAMLreturn(Val_unit);
}

/*
  caml_readdir_batch(dir_handle, buffer, offset, len)

  Reads entries into buffer starting at offset, up to len bytes.
  Format: [kind (1 byte)] [name_len (2 bytes, LE)] [name (name_len bytes)]

  Returns: number of bytes written. 0 indicates End Of Directory.
*/
CAMLprim value caml_readdir_batch(value v_dir, value v_buf, value v_off, value v_len)
{
    CAMLparam4(v_dir, v_buf, v_off, v_len);

    DIR *d = Dir_val(v_dir);
    if (d == NULL)
        caml_failwith("Directory already closed");

    unsigned char *buf = Bytes_val(v_buf);
    int offset = Int_val(v_off);
    int capacity = Int_val(v_len);
    int written = 0;

    struct dirent *de;
    errno = 0;

    while (1)
    {
        /* Check if we have enough space for at least minimal entry (1+2+1=4 bytes) */
        if (written + 4 > capacity)
            break;

        long loc = telldir(d); /* Save position to rewind if entry doesn't fit */
        de = readdir(d);

        if (de == NULL)
            break; /* End of Dir or Error */

        if (strcmp(de->d_name, ".") == 0 || strcmp(de->d_name, "..") == 0)
            continue;

        int name_len = strlen(de->d_name);
        int entry_size = 1 + 2 + name_len;

        if (written + entry_size > capacity)
        {
            /* Not enough space for this entry. Rewind and return what we have. */
            seekdir(d, loc);
            break;
        }

        int kind = map_dtype(de->d_type);

        /* Write [kind:1] */
        buf[offset + written] = (unsigned char)kind;

        /* Write [name_len:2] (Little Endian) */
        buf[offset + written + 1] = (unsigned char)(name_len & 0xFF);
        buf[offset + written + 2] = (unsigned char)((name_len >> 8) & 0xFF);

        /* Write [name] */
        memcpy(buf + offset + written + 3, de->d_name, name_len);

        written += entry_size;
    }

    if (errno != 0 && written == 0)
    {
        /* Error occurred and we wrote nothing */
        uerror("readdir", Val_unit); // Path unknown here, passed unit is vague but uerror expects value
    }

    CAMLreturn(Val_int(written));
}
