/**
 * Copyright (c) 2026, Ronen Druker. All rights reserved.
 *
 * pam_tid_local: Touch ID for sudo, but only when the session is local.
 *
 * macOS's pam_tid shows its Touch ID dialog whenever the calling process belongs to the GUI
 * login session. A tmux (or other multiplexer) server started at the Mac does, so a sudo run
 * in one of its panes while attached over SSH pops the dialog on the Mac's own screen and
 * waits for it forever, instead of asking for the password in the terminal. pam_reattach's
 * ignore_ssh option cannot help: it only skips reattaching, and OpenPAM has no way to skip a
 * later module conditionally.
 *
 * This module wraps pam_tid: when SSH_CONNECTION, SSH_CLIENT or SSH_TTY is set in the calling
 * process it returns PAM_IGNORE, so the stack falls through to the password prompt;
 * otherwise it forwards to pam_tid. Use it in place of pam_tid in /etc/pam.d/sudo_local:
 *
 *   auth  sufficient  /usr/local/lib/pam/pam_tid_local.so
 *
 * Inside tmux the pane's SSH_* variables can be stale (a pane opened at the Mac and later
 * attached over SSH has none); `ua` refreshes them from the tmux session before calling sudo.
 */

#include <dlfcn.h>
#include <security/pam_appl.h>
#include <security/pam_modules.h>
#include <stddef.h>
#include <stdlib.h>

/** System pam_tid module the calls are forwarded to */
#define PAM_TID_PATH "/usr/lib/pam/pam_tid.so.2"

/** Signature shared by the pam_sm_* service functions */
typedef int (*pam_service_fn)(pam_handle_t *pamh, int flags, int argc, const char **argv);

/**
 * Whether the calling process runs on behalf of an SSH session, judged by the variables
 * sshd sets for it.
 *
 * @return 1 when any of SSH_CONNECTION, SSH_CLIENT or SSH_TTY is set and non-empty, else 0
 */
static int is_ssh_session(void) {
    static const char *const vars[] = {"SSH_CONNECTION", "SSH_CLIENT", "SSH_TTY"};
    for (size_t i = 0; i < sizeof vars / sizeof vars[0]; i++) {
        const char *value = getenv(vars[i]);
        if (value != NULL && value[0] != '\0') {
            return 1;
        }
    }
    return 0;
}

/**
 * Call a service function of pam_tid with the same arguments.
 *
 * @param symbol Name of the pam_sm_* function to call
 * @param pamh PAM handle
 * @param flags PAM flags
 * @param argc Number of module options
 * @param argv Module options
 * @return pam_tid's result, or PAM_IGNORE when pam_tid or the function cannot be loaded
 */
static int forward(const char *symbol, pam_handle_t *pamh, int flags, int argc, const char **argv) {
    void *library = dlopen(PAM_TID_PATH, RTLD_NOW | RTLD_LOCAL);
    if (library == NULL) {
        return PAM_IGNORE;
    }
    pam_service_fn fn = (pam_service_fn)dlsym(library, symbol);
    return fn != NULL ? fn(pamh, flags, argc, argv) : PAM_IGNORE;
}

/**
 * Authenticate with Touch ID, unless this is an SSH session.
 *
 * @param pamh PAM handle
 * @param flags PAM flags
 * @param argc Number of module options
 * @param argv Module options
 * @return PAM_IGNORE over SSH, otherwise pam_tid's result
 */
PAM_EXTERN int pam_sm_authenticate(pam_handle_t *pamh, int flags, int argc, const char **argv) {
    return is_ssh_session() ? PAM_IGNORE : forward("pam_sm_authenticate", pamh, flags, argc, argv);
}

/**
 * Set credentials after authentication, mirroring pam_sm_authenticate.
 *
 * @param pamh PAM handle
 * @param flags PAM flags
 * @param argc Number of module options
 * @param argv Module options
 * @return PAM_IGNORE over SSH, otherwise pam_tid's result
 */
PAM_EXTERN int pam_sm_setcred(pam_handle_t *pamh, int flags, int argc, const char **argv) {
    return is_ssh_session() ? PAM_IGNORE : forward("pam_sm_setcred", pamh, flags, argc, argv);
}
