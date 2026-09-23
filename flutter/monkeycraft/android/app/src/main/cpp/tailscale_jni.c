#include <jni.h>
#include <stdlib.h>
#include <string.h>
#include "tailscale.h"

extern int MonkeycraftAndroidInit(char* data_dir);
extern int MonkeycraftDialTimeout(int sd, char* network, char* address, int timeout_millis, int* conn_out);

static const char* text(JNIEnv* e, jstring s) { return s ? (*e)->GetStringUTFChars(e, s, 0) : 0; }
static void done(JNIEnv* e, jstring s, const char* p) { if (s && p) (*e)->ReleaseStringUTFChars(e, s, p); }
JNIEXPORT jint JNICALL Java_com_chenweikeng_monkeycraft_TailscaleNative_configure(JNIEnv* e,jclass c,jstring s){(void)c;const char*p=text(e,s);int r=MonkeycraftAndroidInit((char*)p);done(e,s,p);return r;}
JNIEXPORT jint JNICALL Java_com_chenweikeng_monkeycraft_TailscaleNative_newNode(JNIEnv* e,jclass c){(void)e;(void)c;return tailscale_new();}
JNIEXPORT jint JNICALL Java_com_chenweikeng_monkeycraft_TailscaleNative_setDir(JNIEnv* e,jclass c,jint h,jstring s){(void)c;const char*p=text(e,s);int r=tailscale_set_dir(h,p);done(e,s,p);return r;}
JNIEXPORT jint JNICALL Java_com_chenweikeng_monkeycraft_TailscaleNative_setHostname(JNIEnv* e,jclass c,jint h,jstring s){(void)c;const char*p=text(e,s);int r=tailscale_set_hostname(h,p);done(e,s,p);return r;}
JNIEXPORT jint JNICALL Java_com_chenweikeng_monkeycraft_TailscaleNative_start(JNIEnv* e,jclass c,jint h){(void)e;(void)c;return tailscale_start(h);}
JNIEXPORT jint JNICALL Java_com_chenweikeng_monkeycraft_TailscaleNative_close(JNIEnv* e,jclass c,jint h){(void)e;(void)c;return tailscale_close(h);}
JNIEXPORT jstring JNICALL Java_com_chenweikeng_monkeycraft_TailscaleNative_error(JNIEnv* e,jclass c,jint h){(void)c;char b[2048]={0};tailscale_errmsg(h,b,sizeof b);return (*e)->NewStringUTF(e,b);}
JNIEXPORT jstring JNICALL Java_com_chenweikeng_monkeycraft_TailscaleNative_status(JNIEnv* e,jclass c,jint h){(void)c;char*j=0;if(tailscale_status_json(h,&j)||!j)return 0;jstring r=(*e)->NewStringUTF(e,j);free(j);return r;}
JNIEXPORT jobjectArray JNICALL Java_com_chenweikeng_monkeycraft_TailscaleNative_loopback(JNIEnv* e,jclass c,jint h){(void)c;char a[64]={0},p[33]={0},k[33]={0};if(tailscale_loopback(h,a,sizeof a,p,k))return 0;jclass s=(*e)->FindClass(e,"java/lang/String");jobjectArray r=(*e)->NewObjectArray(e,3,s,0);(*e)->SetObjectArrayElement(e,r,0,(*e)->NewStringUTF(e,a));(*e)->SetObjectArrayElement(e,r,1,(*e)->NewStringUTF(e,p));(*e)->SetObjectArrayElement(e,r,2,(*e)->NewStringUTF(e,k));return r;}
JNIEXPORT jint JNICALL Java_com_chenweikeng_monkeycraft_TailscaleNative_dial(JNIEnv* e,jclass c,jint h,jstring n,jstring a,jint timeout){(void)c;const char*np=text(e,n),*ap=text(e,a);int fd=-1,r=MonkeycraftDialTimeout(h,(char*)np,(char*)ap,timeout,&fd);done(e,n,np);done(e,a,ap);return r ? -1 : fd;}
