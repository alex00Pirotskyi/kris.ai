#ifdef __APPLE__
#define _DARWIN_C_SOURCE 1
#else
#define _XOPEN_SOURCE 700
#endif
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/select.h>
#include <sys/types.h>
#ifdef __APPLE__
#include <util.h>
#else
#include <pty.h>
#endif
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

static long long now_ms(void) { struct timespec v; if (clock_gettime(CLOCK_MONOTONIC,&v)!=0) return -1; return (long long)v.tv_sec*1000LL+v.tv_nsec/1000000LL; }
static int write_all(int fd,const char *b,size_t n){size_t o=0;while(o<n){ssize_t w=write(fd,b+o,n-o);if(w<0&&errno==EINTR)continue;if(w<=0)return 0;o+=(size_t)w;}return 1;}
static int read_until(int fd,char *out,size_t cap,size_t *used,const char *marker,long long deadline){while(*used+1<cap&&now_ms()<deadline){fd_set set;FD_ZERO(&set);FD_SET(fd,&set);struct timeval wait={.tv_sec=0,.tv_usec=100000};int ready=select(fd+1,&set,NULL,NULL,&wait);if(ready<0&&errno==EINTR)continue;if(ready<=0)continue;ssize_t c=read(fd,out+*used,cap-*used-1);if(c<0&&errno==EINTR)continue;if(c<=0)break;*used+=(size_t)c;out[*used]='\0';if(strstr(out,marker)!=NULL)return 1;}return strstr(out,marker)!=NULL;}
static pid_t parse_descendant(const char *text){const char *p=strstr(text,"DESC_PID=");if(!p)return -1;long v=strtol(p+9,NULL,10);return v>1?(pid_t)v:-1;}
int main(void){
 int master=-1;struct winsize initial={.ws_row=24,.ws_col=80};long long started=now_ms();pid_t child=forkpty(&master,NULL,NULL,&initial);if(child<0)return 2;
 if(child==0){execl("/bin/sh","sh","-c","IFS= read -r line; printf '\\033[31mKRISTIN_NATIVE_ANSI\\033[0m KRISTIN_NATIVE_UNICODE_✓ %s\\n' \"$line\"; (sleep 30) & d=$!; printf 'DESC_PID=%s\\n' \"$d\"; sleep 0.35; printf 'KRISTIN_DETACHED_OUTPUT\\n'; wait",(char*)NULL);_exit(127);}
 struct winsize resized={.ws_row=41,.ws_col=123};int resize_ok=ioctl(master,TIOCSWINSZ,&resized)==0;const char *input="INPUT_OK\n";int input_ok=write_all(master,input,strlen(input));
 char output[32768];size_t used=0;output[0]='\0';int initial_ok=read_until(master,output,sizeof(output),&used,"DESC_PID=",now_ms()+5000);size_t cursor=used;pid_t descendant=parse_descendant(output);
 struct timespec detached={.tv_sec=0,.tv_nsec=650000000L};nanosleep(&detached,NULL);int detached_ok=read_until(master,output,sizeof(output),&used,"KRISTIN_DETACHED_OUTPUT",now_ms()+5000);const char *backlog=output+cursor;
 int ansi=strstr(output,"KRISTIN_NATIVE_ANSI")!=NULL;int unicode=strstr(output,"KRISTIN_NATIVE_UNICODE_")!=NULL;int output_while_detached=detached_ok&&strstr(backlog,"KRISTIN_DETACHED_OUTPUT")!=NULL;int replay_exact=output_while_detached;int no_loss=cursor>0&&used>=cursor;
 errno=0;int group_term=kill(-child,SIGTERM)==0;int group_missing=!group_term&&errno==ESRCH;int direct_term=1;if(group_missing){errno=0;direct_term=kill(child,SIGTERM)==0||errno==ESRCH;}int term_ok=group_term||(group_missing&&direct_term);
 struct timespec grace={.tv_sec=0,.tv_nsec=250000000L};nanosleep(&grace,NULL);int status=0;int reaped=0;long long reap_deadline=now_ms()+1500;while(now_ms()<reap_deadline){pid_t w=waitpid(child,&status,WNOHANG);if(w==child){reaped=1;break;}if(w<0&&errno==ECHILD){reaped=1;break;}if(w<0&&errno!=EINTR)break;struct timespec poll={.tv_sec=0,.tv_nsec=25000000L};nanosleep(&poll,NULL);}if(!reaped){(void)kill(-child,SIGKILL);(void)kill(child,SIGKILL);reap_deadline=now_ms()+1500;while(now_ms()<reap_deadline){pid_t w=waitpid(child,&status,WNOHANG);if(w==child||(w<0&&errno==ECHILD)){reaped=1;break;}if(w<0&&errno!=EINTR)break;struct timespec poll={.tv_sec=0,.tv_nsec=25000000L};nanosleep(&poll,NULL);}}
 int no_group=0;long long deadline=now_ms()+2500;while(now_ms()<deadline){errno=0;if(kill(-child,0)!=0&&errno==ESRCH){no_group=1;break;}struct timespec poll={.tv_sec=0,.tv_nsec=25000000L};nanosleep(&poll,NULL);}int descendant_dead=0;if(descendant>1){long long descendant_deadline=now_ms()+2500;while(now_ms()<descendant_deadline){errno=0;if(kill(descendant,0)!=0&&errno==ESRCH){descendant_dead=1;break;}struct timespec poll={.tv_sec=0,.tv_nsec=25000000L};nanosleep(&poll,NULL);}}close(master);
 int passed=input_ok&&resize_ok&&initial_ok&&ansi&&unicode&&output_while_detached&&replay_exact&&no_loss&&descendant>1&&term_ok&&reaped&&no_group&&descendant_dead;long long duration=now_ms()-started;
 printf("{\"schemaVersion\":\"3.0.0\",\"receiptType\":\"p2-native-supplementary-smoke-v1\",\"completionEligible\":false,\"status\":\"%s\",\"coldStartMs\":%lld,\"observed\":{\"interactiveInput\":%s,\"resize\":%s,\"ansi\":%s,\"unicode\":%s,\"sameDescriptorDelayedOutput\":%s,\"processTreeTermination\":%s},\"notMeasured\":[\"consumer-detach\",\"durable-cursor-reconnect\",\"exact-backlog-replay\"],\"childPid\":%ld,\"descendantPid\":%ld,\"outputBytes\":%zu}\n",passed?"passed":"failed",duration,input_ok?"true":"false",resize_ok?"true":"false",ansi?"true":"false",unicode?"true":"false",output_while_detached?"true":"false",(no_group&&descendant_dead)?"true":"false",(long)child,(long)descendant,used);return passed?0:1;
}
