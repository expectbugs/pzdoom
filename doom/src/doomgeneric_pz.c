// doomgeneric_pz.c — Project Zomboid backend for doomgeneric
//
// Video: writes raw RGBA frames (320x200x4) to a saved stdout fd
// Input: reads key events (2 bytes: pressed, keycode) from stdin
// Audio: handled by SDL2_mixer via i_sdlsound.c/i_sdlmusic.c (separate)
//
// CRITICAL: DOOM's codebase has ~289 printf/puts calls that write to stdout.
// main() first dup()s the original stdout fd for frame data (s_FrameOut) and
// reopens stdout on the null device, so no text can ever enter the frame pipe.
//
// Protocol:
//   stdout (saved fd): [RGBA pixels, 256000 bytes per frame, continuous]
//   stdin:             [pressed:u8, doom_keycode:u8] per event, non-blocking reads
//   stdin EOF or a failed frame write = host went away -> exit(0)

#include "doomgeneric.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <errno.h>

#ifdef _WIN32
#include <windows.h>
#include <io.h>
#include <fcntl.h>
#else
#include <unistd.h>
#include <fcntl.h>
#include <time.h>
#endif

// Key event queue (same pattern as doomgeneric_sdl.c)
#define KEYQUEUE_SIZE 32
static unsigned short s_KeyQueue[KEYQUEUE_SIZE];
static unsigned int s_KeyQueueWriteIndex = 0;
static unsigned int s_KeyQueueReadIndex = 0;

// RGBA output buffer (320 * 200 * 4 = 256000 bytes)
static uint8_t s_RgbaBuf[DOOMGENERIC_RESX * DOOMGENERIC_RESY * 4];

// Frame output stream — writes to the ORIGINAL stdout fd (before redirect)
// All printf/puts in DOOM go to the redirected stdout (→ stderr → /dev/null)
static FILE *s_FrameOut = NULL;

// Startup time for DG_GetTicksMs
#ifdef _WIN32
static DWORD s_StartTicks = 0;
#else
static struct timespec s_StartTime;
#endif

static void addKeyToQueue(int pressed, unsigned char keyCode)
{
    unsigned short keyData = (pressed << 8) | keyCode;
    s_KeyQueue[s_KeyQueueWriteIndex] = keyData;
    s_KeyQueueWriteIndex++;
    s_KeyQueueWriteIndex %= KEYQUEUE_SIZE;
}

// The host (PZFB) closes our stdin when it ends the session. Treat that EOF
// as "quit now" so a stop doesn't have to wait for a frame write to fail or
// for a signal. DOOM has nothing to save here, so exit(0) is a clean exit.
static void hostClosedStdin(void)
{
    exit(0);
}

// Read all available key events from stdin (non-blocking)
static void readStdinKeys(void)
{
#ifdef _WIN32
    HANDLE hStdin = GetStdHandle(STD_INPUT_HANDLE);
    DWORD avail = 0;
    for (;;) {
        if (!PeekNamedPipe(hStdin, NULL, 0, NULL, &avail, NULL)) {
            // Parent closed the pipe (ERROR_BROKEN_PIPE). Other failures
            // (e.g. stdin is a console, not a pipe) are left alone.
            if (GetLastError() == ERROR_BROKEN_PIPE) {
                hostClosedStdin();
            }
            break;
        }
        if (avail < 2) {
            break;
        }
        uint8_t buf[2];
        DWORD bytesRead = 0;
        if (ReadFile(hStdin, buf, 2, &bytesRead, NULL) && bytesRead == 2) {
            addKeyToQueue(buf[0], buf[1]);
        } else {
            break;
        }
    }
#else
    // stdin is set to non-blocking in DG_Init.
    // Buffer partial bytes across calls to handle split 2-byte events.
    static int s_pendingByte = -1;
    uint8_t buf[2];

    while (1) {
        // Complete a partial event from the previous call
        if (s_pendingByte >= 0) {
            buf[0] = (uint8_t)s_pendingByte;
            s_pendingByte = -1;
            ssize_t n = read(STDIN_FILENO, &buf[1], 1);
            if (n == 1) {
                addKeyToQueue(buf[0], buf[1]);
                continue;
            } else if (n == 0) {
                hostClosedStdin(); // EOF: parent closed the pipe
            } else if (errno == EAGAIN || errno == EWOULDBLOCK) {
                // Byte 2 not available yet — re-buffer byte 0 for next call
                s_pendingByte = buf[0];
                break;
            } else {
                // Real error — discard partial event
                break;
            }
        }

        ssize_t n = read(STDIN_FILENO, buf, 2);
        if (n == 2) {
            addKeyToQueue(buf[0], buf[1]);
        } else if (n == 1) {
            s_pendingByte = buf[0]; // buffer for next call
            break;
        } else if (n == 0) {
            hostClosedStdin(); // EOF: parent closed the pipe
        } else {
            break; // EAGAIN or real error
        }
    }
#endif
}

// Claim the original stdout for frame output and make DOOM's own stdout spam
// disappear. Must run before ANY stdio output, so main() calls it first.
//
// The frame stream is s_FrameOut on a dup of the original fd 1. stdout itself
// is then reopened on the null device at the FILE level. Earlier versions did
// dup2(stderr, stdout) instead; under Wine/Proton that silently fails when the
// host hands the child a file or NUL as stderr, and DOOM's ~1.6 KB startup
// banner went down the frame pipe, shifting every frame (verified 0.3.0).
// freopen() does not depend on stderr at all, and keeps the stderr log that
// PZFB shows on errors free of printf noise.
static void setupFrameOutput(void)
{
#ifdef _WIN32
    // Binary mode on the std handles (prevent \n → \r\n conversion)
    _setmode(_fileno(stdout), _O_BINARY);
    _setmode(_fileno(stdin), _O_BINARY);

    int frame_fd = _dup(_fileno(stdout));
    s_FrameOut = _fdopen(frame_fd, "wb");
    if (freopen("NUL", "w", stdout) == NULL) {
        // freopen closed the old stream first; printf() now fails harmlessly.
    }
#else
    int frame_fd = dup(STDOUT_FILENO);
    s_FrameOut = fdopen(frame_fd, "wb");
    if (freopen("/dev/null", "w", stdout) == NULL) {
        // freopen closed the old stream first; printf() now fails harmlessly.
    }

    // Try to increase pipe buffer for smoother frame delivery
#ifdef F_SETPIPE_SZ
    fcntl(frame_fd, F_SETPIPE_SZ, 1048576); // 1MB, ignore failure
#endif
#endif
}

void DG_Init(void)
{
    if (!s_FrameOut) {
        setupFrameOutput(); // main() normally did this already
    }
#ifdef _WIN32
    s_StartTicks = GetTickCount();
#else
    // Set stdin to non-blocking
    int flags = fcntl(STDIN_FILENO, F_GETFL, 0);
    if (flags != -1) {
        fcntl(STDIN_FILENO, F_SETFL, flags | O_NONBLOCK);
    }

    clock_gettime(CLOCK_MONOTONIC, &s_StartTime);
#endif
}

void DG_DrawFrame(void)
{
    // Convert DG_ScreenBuffer from 0x00RRGGBB (uint32) to RGBA bytes
    // Verified from i_video.c: red.offset=16, green.offset=8, blue.offset=0
    const int numPixels = DOOMGENERIC_RESX * DOOMGENERIC_RESY;
    for (int i = 0; i < numPixels; i++) {
        uint32_t p = DG_ScreenBuffer[i];
        s_RgbaBuf[i * 4 + 0] = (p >> 16) & 0xFF; // R
        s_RgbaBuf[i * 4 + 1] = (p >> 8)  & 0xFF; // G
        s_RgbaBuf[i * 4 + 2] = p & 0xFF;          // B
        s_RgbaBuf[i * 4 + 3] = 0xFF;              // A (opaque)
    }

    size_t written = fwrite(s_RgbaBuf, 1, sizeof(s_RgbaBuf), s_FrameOut);
    if (written != sizeof(s_RgbaBuf)) {
        // Pipe closed (Java killed us) — exit gracefully
        exit(0);
    }
    fflush(s_FrameOut);

    // Also poll for input during frame draw (same timing as SDL backend)
    readStdinKeys();
}

void DG_SleepMs(uint32_t ms)
{
#ifdef _WIN32
    Sleep(ms);
#else
    usleep(ms * 1000);
#endif
}

uint32_t DG_GetTicksMs(void)
{
#ifdef _WIN32
    return GetTickCount() - s_StartTicks;
#else
    struct timespec now;
    clock_gettime(CLOCK_MONOTONIC, &now);
    return (uint32_t)((now.tv_sec - s_StartTime.tv_sec) * 1000 +
                      (now.tv_nsec - s_StartTime.tv_nsec) / 1000000);
#endif
}

int DG_GetKey(int *pressed, unsigned char *doomKey)
{
    if (s_KeyQueueReadIndex == s_KeyQueueWriteIndex) {
        return 0; // queue empty
    }

    unsigned short keyData = s_KeyQueue[s_KeyQueueReadIndex];
    s_KeyQueueReadIndex++;
    s_KeyQueueReadIndex %= KEYQUEUE_SIZE;

    *pressed = keyData >> 8;
    *doomKey = keyData & 0xFF;

    return 1;
}

void DG_SetWindowTitle(const char *title)
{
    // Headless — no window title
    (void)title;
}

int main(int argc, char **argv)
{
    setupFrameOutput(); // before anything can printf()
    doomgeneric_Create(argc, argv);

    for (;;) {
        doomgeneric_Tick();
    }

    return 0;
}
