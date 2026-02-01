/* search_stubs.c - Mmap based regex search */

#include <sys/mman.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>
#include <regex.h>
#include <string.h>
#include <errno.h>

#include <caml/mlvalues.h>
#include <caml/memory.h>
#include <caml/alloc.h>
#include <caml/fail.h>
#include <caml/unixsupport.h>

/*
   caml_search_regex(v_path, v_pattern)

   Returns:
     1 (true)  if pattern matches content
     0 (false) if pattern does not match
    -1 (error) if something went wrong (e.g. regex compilation failed, mmap failed)
               allowing fallback to OCaml implementation.
*/
CAMLprim value caml_search_regex(value v_path, value v_pattern)
{
    CAMLparam2(v_path, v_pattern);
    const char *path = String_val(v_path);
    const char *pattern = String_val(v_pattern);
    int ret = 0;

    /* 1. Compile Regex */
    regex_t regex;
    /* Use REG_EXTENDED for modern syntax, REG_NOSUB for speed (we only care if it matches) */
    /* Note: macOS/BSD regex might differ slightly from GNU, hence fallback strategy is crucial. */
    if (regcomp(&regex, pattern, REG_EXTENDED | REG_NOSUB | REG_NEWLINE) != 0)
    {
        /* Regex compilation failed - likely unsupported syntax */
        CAMLreturn(Val_int(-1));
    }

    /* 2. Open File */
    int fd = open(path, O_RDONLY);
    if (fd == -1)
    {
        regfree(&regex);
        /* If file cannot be opened, we can't search it. Return -1 to let OCaml implementation handle it (or fail there). */
        CAMLreturn(Val_int(-1));
    }

    /* 3. Get file size */
    struct stat st;
    if (fstat(fd, &st) == -1)
    {
        close(fd);
        regfree(&regex);
        CAMLreturn(Val_int(-1));
    }

    if (st.st_size == 0)
    {
        /* Empty file matches nothing usually, checks against empty string?
           Let's return 0 (no match) or check against empty buffer. */
        /* regexec on empty string: */
        int match = regexec(&regex, "", 0, NULL, 0);
        close(fd);
        regfree(&regex);
        CAMLreturn(Val_int(match == 0 ? 1 : 0));
    }

    /* 4. Mmap */
    /* MAP_PRIVATE ensures we don't write back changes (though we are PROT_READ anyway) */
    void *addr = mmap(NULL, st.st_size, PROT_READ, MAP_PRIVATE, fd, 0);
    if (addr == MAP_FAILED)
    {
        close(fd);
        regfree(&regex);
        CAMLreturn(Val_int(-1));
    }

    /* 5. Execute Regex */
    /* regexec expects null-terminated string usually, but with REG_STARTEND (BSD extension)
       we could specify length. However, standard POSIX regexec works on null-terminated strings.
       mmap memory is NOT null-terminated!

       CRITICAL: POSIX regexec does NOT support length argument.
       Standard regexec will run off the end of mmap if no null byte is found!

       Solutions:
       A. Linux/BSD often have REG_STARTEND (non-standard but common).
       B. Search chunk by chunk? (Complex)
       C. Safe fallback: If file is huge, this is risky without REG_STARTEND.
          macOS (BSD) has REG_STARTEND. Linux (glibc) has REG_STARTEND.
          We should try to use REG_STARTEND.
    */

#ifdef REG_STARTEND
    regmatch_t pmatch[1];
    pmatch[0].rm_so = 0;
    pmatch[0].rm_eo = st.st_size;

    int rc = regexec(&regex, (const char *)addr, 0, pmatch, REG_STARTEND);
    if (rc == 0)
    {
        ret = 1; /* Match */
    }
    else
    {
        ret = 0; /* No match (REG_NOMATCH) */
    }
#else
    /* Without REG_STARTEND, we cannot safely use regexec on mmap'd data unless we know it has nulls.
       We must fallback. */
    ret = -1;
#endif

    /* 6. Cleanup */
    munmap(addr, st.st_size);
    close(fd);
    regfree(&regex);

    CAMLreturn(Val_int(ret));
}
