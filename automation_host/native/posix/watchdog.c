#define _POSIX_C_SOURCE 200809L
#include <errno.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/select.h>
#include <sys/stat.h>
#include <sys/time.h>
#include <time.h>
#include <unistd.h>
#ifdef __APPLE__
#include <libproc.h>
#endif

static long long monotonic_ms(void) {
  struct timespec value;
  if (clock_gettime(CLOCK_MONOTONIC, &value) != 0) return -1;
  return (long long)value.tv_sec * 1000LL + value.tv_nsec / 1000000LL;
}

static int parse_positive(const char *text, long min, long max, long *value) {
  char *end = NULL;
  errno = 0;
  long parsed = strtol(text, &end, 10);
  if (errno || !end || *end != '\0' || parsed < min || parsed > max) return 0;
  *value = parsed;
  return 1;
}

static int linux_identity(pid_t pid, char *buffer, size_t size, uid_t *uid) {
#ifdef __linux__
  char path[64];
  snprintf(path, sizeof(path), "/proc/%ld/stat", (long)pid);
  FILE *file = fopen(path, "r");
  if (!file) return 0;
  char line[4096];
  if (!fgets(line, sizeof(line), file)) { fclose(file); return 0; }
  fclose(file);
  char *close = strrchr(line, ')');
  if (!close) return 0;
  char *cursor = close + 2;
  char *save = NULL;
  char *token = strtok_r(cursor, " ", &save);
  int field = 3;
  const char *start = NULL;
  while (token) {
    if (field == 22) { start = token; break; }
    token = strtok_r(NULL, " ", &save);
    field++;
  }
  if (!start) return 0;
  struct stat metadata;
  snprintf(path, sizeof(path), "/proc/%ld", (long)pid);
  if (stat(path, &metadata) != 0) return 0;
  *uid = metadata.st_uid;
  snprintf(buffer, size, "linux:%ld:%s", (long)pid, start);
  buffer[strcspn(buffer, "\r\n")] = '\0';
  return 1;
#else
  (void)pid; (void)buffer; (void)size; (void)uid;
  return 0;
#endif
}

static int count_group_members(pid_t pgid) {
  FILE *stream = popen("ps -axo pid=,pgid=", "r");
  if (!stream) return -1;
  char line[256];
  int count = 0;
  while (fgets(line, sizeof(line), stream)) {
    long observed_pid = 0;
    long observed_pgid = 0;
    if (sscanf(line, "%ld %ld", &observed_pid, &observed_pgid) == 2 &&
        observed_pid > 1 && observed_pgid == (long)pgid) {
      count++;
    }
  }
  const int status = pclose(stream);
  return status == 0 ? count : -1;
}

static int mac_identity(pid_t pid, char *buffer, size_t size, uid_t *uid) {
#ifdef __APPLE__
  struct proc_bsdinfo info;
  int bytes = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, sizeof(info));
  if (bytes != sizeof(info)) return 0;
  *uid = info.pbi_uid;
  snprintf(buffer, size, "darwin:%ld:%llu:%llu", (long)pid,
           (unsigned long long)info.pbi_start_tvsec,
           (unsigned long long)info.pbi_start_tvusec);
  return 1;
#else
  (void)pid; (void)buffer; (void)size; (void)uid;
  return 0;
#endif
}

int main(int argc, char **argv) {
  if (argc == 3 && strcmp(argv[1], "--identity") == 0) {
    long pid_value;
    if (!parse_positive(argv[2], 2, 2147483647L, &pid_value)) return 2;
    pid_t pid = (pid_t)pid_value;
    pid_t pgid = getpgid(pid);
    char token[256]; uid_t uid = (uid_t)-1;
    if (pgid <= 1 || (!linux_identity(pid, token, sizeof(token), &uid) &&
                      !mac_identity(pid, token, sizeof(token), &uid))) return 3;
    fprintf(stdout, "{\"pid\":%ld,\"pgid\":%ld,\"uid\":%ld,\"startToken\":\"%s\"}\n",
            (long)pid, (long)pgid, (long)uid, token);
    return 0;
  }
  if (argc != 11 || strcmp(argv[1], "--watch-pid") != 0 ||
      strcmp(argv[3], "--pgid") != 0 ||
      strcmp(argv[5], "--start-token") != 0 ||
      strcmp(argv[7], "--uid") != 0 ||
      strcmp(argv[9], "--timeout-ms") != 0) {
    fprintf(stderr, "usage: %s --watch-pid PID --pgid PGID --start-token TOKEN --uid UID --timeout-ms MS\n", argv[0]);
    return 2;
  }
  long pid_value, pgid_value, uid_value, timeout;
  if (!parse_positive(argv[2], 2, 2147483647L, &pid_value) ||
      !parse_positive(argv[4], 2, 2147483647L, &pgid_value) ||
      !parse_positive(argv[8], 0, 2147483647L, &uid_value) ||
      !parse_positive(argv[10], 100, 3600000L, &timeout)) {
    fprintf(stderr, "invalid numeric argument\n");
    return 2;
  }
  pid_t pid = (pid_t)pid_value;
  pid_t pgid = (pid_t)pgid_value;
  if (getpgid(pid) != pgid || pgid != pid) {
    fprintf(stderr, "unmanaged or unsafe process group\n");
    return 3;
  }
  char actual[256];
  uid_t actual_uid = (uid_t)-1;
  if (!linux_identity(pid, actual, sizeof(actual), &actual_uid) &&
      !mac_identity(pid, actual, sizeof(actual), &actual_uid)) {
    fprintf(stderr, "cannot establish process identity\n");
    return 3;
  }
  if (actual_uid != (uid_t)uid_value || strcmp(actual, argv[6]) != 0 || actual_uid != getuid()) {
    fprintf(stderr, "process identity or ownership mismatch\n");
    return 3;
  }

  long long last = monotonic_ms();
  if (last < 0) return 4;
  const char *reason = "heartbeat_timeout";
  char line[64];
  while (1) {
    if (getpgid(pid) != pgid) return 0;
    char current[256]; uid_t current_uid = (uid_t)-1;
    if ((!linux_identity(pid, current, sizeof(current), &current_uid) &&
         !mac_identity(pid, current, sizeof(current), &current_uid)) ||
        strcmp(current, actual) != 0 || current_uid != actual_uid) {
      fprintf(stderr, "process identity changed\n");
      return 3;
    }
    fd_set set; FD_ZERO(&set); FD_SET(STDIN_FILENO, &set);
    struct timeval wait = {0, 100000};
    int ready = select(STDIN_FILENO + 1, &set, NULL, NULL, &wait);
    if (ready > 0 && fgets(line, sizeof(line), stdin)) {
      if (!strncmp(line, "beat", 4)) last = monotonic_ms();
      else if (!strncmp(line, "kill", 4)) { reason = "explicit_kill"; break; }
    } else if (ready > 0) {
      reason = "heartbeat_pipe_closed";
      break;
    } else if (ready < 0 && errno != EINTR) {
      return 4;
    }
    if (monotonic_ms() - last > timeout) break;
    if (kill(pid, 0) < 0 && errno == ESRCH) return 0;
  }
  const int active_before_kill = count_group_members(pgid);
  if (active_before_kill < 1) return 5;
  if (kill(-pgid, SIGTERM) != 0 && errno != ESRCH) return 5;
  struct timespec pause_time = {0, 250000000L};
  nanosleep(&pause_time, NULL);
  if (kill(-pgid, SIGKILL) != 0 && errno != ESRCH) return 5;
  int group_gone = 0;
  for (int attempt = 0; attempt < 200; ++attempt) {
    if (kill(-pgid, 0) != 0 && errno == ESRCH) {
      group_gone = 1;
      break;
    }
    struct timespec verify_pause = {0, 25000000L};
    nanosleep(&verify_pause, NULL);
  }
  if (!group_gone) return 5;
  fprintf(stdout, "{\"status\":\"killed\",\"pid\":%ld,\"pgid\":%ld,\"uid\":%ld,\"startToken\":\"%s\",\"identityVerified\":true,\"activeProcessesBeforeKill\":%d,\"descendantProcessCount\":%d,\"activeProcesses\":0,\"zeroSurvivingDescendants\":true,\"reason\":\"%s\"}\n",
          (long)pid, (long)pgid, (long)actual_uid, actual,
          active_before_kill, active_before_kill > 0 ? active_before_kill - 1 : 0,
          reason);
  fflush(stdout);
  return 0;
}
