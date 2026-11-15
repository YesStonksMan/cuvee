// SPDX-License-Identifier: LGPL-2.1-or-later
// msync-leak.exe [SECONDS] — the usual Windows worker loop: threads wait on (a stop event never set, a work event
// set all the time). With CrossOver 26.3's msync, a wait that sees the work event while the server has not yet
// answered returned without unregistering: one node stayed on the stop event each time. After 0x80000 of them
// wineserver printed "msync: warn: node memory pool exhausted" on every later wait (Cuvee.log reached 10 GB).
// tests/msync-leak.sh runs this in a throwaway bottle and fails if that line shows up.
// Build: x86_64-w64-mingw32-gcc -O2 tests/msync-leak.c -o tests/msync-leak.exe
#include <windows.h>
#include <stdio.h>
#include <stdlib.h>

static HANDLE stop, work;
static volatile LONG running = 1;
static volatile LONG waits;

static DWORD WINAPI waiter(void *arg)
{
    HANDLE objs[2] = { stop, work };
    while (running) { WaitForMultipleObjects(2, objs, FALSE, 50); InterlockedIncrement(&waits); }
    return 0;
}

static DWORD WINAPI setter(void *arg)
{
    while (running) { SetEvent(work); Sleep(0); }
    return 0;
}

int main(int argc, char **argv)
{
    int seconds = argc > 1 ? atoi(argv[1]) : 60, i;
    HANDLE threads[4];

    stop = CreateEventA(NULL, TRUE, FALSE, NULL);
    work = CreateEventA(NULL, FALSE, FALSE, NULL);
    for (i = 0; i < 3; i++) threads[i] = CreateThread(NULL, 0, waiter, NULL, 0, NULL);
    threads[3] = CreateThread(NULL, 0, setter, NULL, 0, NULL);
    Sleep(seconds * 1000);
    running = 0;
    SetEvent(work);
    WaitForMultipleObjects(4, threads, TRUE, 5000);
    printf("waits: %ld\n", waits);
    return 0;
}
