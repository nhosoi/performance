/** BEGIN COPYRIGHT BLOCK
 * This Program is free software; you can redistribute it and/or modify it under
 * the terms of the GNU General Public License as published by the Free Software
 * Foundation; version 2 of the License.
 * 
 * This Program is distributed in the hope that it will be useful, but WITHOUT
 * ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
 * FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
 * 
 * You should have received a copy of the GNU General Public License along with
 * this Program; if not, write to the Free Software Foundation, Inc., 59 Temple
 * Place, Suite 330, Boston, MA 02111-1307 USA.
 * 
 * In addition, as a special exception, Red Hat, Inc. gives You the additional
 * right to link the code of this Program with code not covered under the GNU
 * General Public License ("Non-GPL Code") and to distribute linked combinations
 * including the two, subject to the limitations in this paragraph. Non-GPL Code
 * permitted under this exception must only link to the code of this Program
 * through those well defined interfaces identified in the file named EXCEPTION
 * found in the source code files (the "Approved Interfaces"). The files of
 * Non-GPL Code may instantiate templates or use macros or inline functions from
 * the Approved Interfaces without causing the resulting work to be covered by
 * the GNU General Public License. Only Red Hat, Inc. may make changes or
 * additions to the list of Approved Interfaces. You must obey the GNU General
 * Public License in all respects for all of the Program code and other code used
 * in conjunction with the Program except the Non-GPL Code covered by this
 * exception. If you modify this file, you may extend this exception to your
 * version of the file, but you are not obligated to do so. If you do not wish to
 * provide this exception without modification, you must delete this exception
 * statement from your version and license this file solely under the GPL without
 * exception. 
 * 
 * Copyright (C) 2011 Red Hat, Inc.
 * All rights reserved.
 * END COPYRIGHT BLOCK **/

#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <string.h>
#include <time.h>     /* nanosleep */
#include <sys/time.h> /* gettimeofday */
#include <ldap.h>     /* ldap functions */
#include <errno.h>    /* perror */
#include <getopt.h>   /* getopt */
#include <pthread.h>  /* pthread */
#include <math.h>     /* sqrt */

/* number of entries to add */
unsigned int entrynum = 1000;

/* measure the delta every <interval> */
unsigned int interval = 100;

/* nano second to wait between 2 adds */
long nanosec = 0;

/* base dn */
char *basedn = NULL;

/* verbose mode */
int verbose = 0;

typedef struct {
    unsigned int id;
    struct timeval start;
    struct timeval end;
    struct timeval delta;
} perfItem;

struct thread_arg {
    int threadid;
    int rc;
};

/* length of perfitem array per thread */
unsigned int perfitemlen = 0;

/* length of perfitem array in total */
unsigned int totalperfitemlen = 0;

/* 
 * in case thread count > 1, perfitems array looks like this:
 * perfitems[0, ... perfitemlen-1, perfitemlen, ... n*perfitemlen-1 ]
 *           ^                     ^                ^
 *           thread 0              thread 1         thread n-1
 */
perfItem *perfitems = NULL;

char *masterhost = NULL;
char *replicahost = NULL;

int masterport = 389;
int replicaport = 390;

char *masterbdn = NULL;
char *masterbpw = NULL;

char *replicabdn = NULL;
char *replicabpw = NULL;

int threads = 1;
int synchronous = 1;

char *uidprefix = NULL;

#define UNUSED ((unsigned int)(-1))

static void usage(char *me);
static int check_servers();
static void *master_thread(void *ptr);
static void *replica_thread(void *ptr);
static int print_stats();

/*
 * Usage: $0 -h <masterhost> -p <masterport> 
 *           -i <replicahost> -q <replicaport>
 *           -D <masterbdn> -w <masterbpw> 
 *           -d <replicabdn> -W <replicabpw>
 *           -n <number_of_entries> -I <interval_to_measure> 
 *           -b <basedn> -s <nanosec> -t <threads>
 *           -e <uid_prefix>
 *           -a -v
 *
 *           -s <nanosec>:  nano second to wait between 2 adds
 *           -e <uid_prefix>: "uid=<uid_prefix>.<thread>.<seqnum>"
 *           -a: asynchronous add
 *           -v: verbose
 */
int
main(int ac, char **av)
{
    int rc;
    int opt;
    int i;
    perfItem *pip = NULL;
    pthread_t *mthreads, *rthreads;
    char *me = strdup(*av);
    struct thread_arg *mthread_args = NULL;
    struct thread_arg *rthread_args = NULL;

    masterhost = strdup("localhost");
    replicahost = strdup("localhost");
    masterbdn = strdup("cn=directory manager");
    masterbpw = strdup("password");
    replicabdn = strdup("cn=directory manager");
    replicabpw = strdup("password");
    basedn = strdup("dc=example,dc=com");;

    /* parse options */
    while ((opt = getopt(ac, av, "h:p:i:q:D:w:d:W:b:n:I:s:t:e:av")) != -1) {
        switch (opt) {
        case 'h': /* master host */
            if (masterhost) {
                free(masterhost);
            }
            masterhost = strdup(optarg);
            break;
        case 'p': /* master port */
            masterport = atoi(optarg);
            break;
        case 'i': /* replica host */
            if (replicahost) {
                free(replicahost);
            }
            replicahost = strdup(optarg);
            break;
        case 'q': /* replica port */
            replicaport = atoi(optarg);
            break;
        case 'D': /* master bind dn */
            if (masterbdn) {
                free(masterbdn);
            }
            masterbdn = strdup(optarg);
            break;
        case 'w': /* master bind password */
            if (masterbpw) {
                free(masterbpw);
            }
            masterbpw = strdup(optarg);
            break;
        case 'd': /* replica bind dn */
            if (replicabdn) {
                free(replicabdn);
            }
            replicabdn = strdup(optarg);
            break;
        case 'W': /* replica bind password */
            if (replicabpw) {
                free(replicabpw);
            }
            replicabpw = strdup(optarg);
            break;
        case 'b': /* base dn */
            if (basedn) {
                free(basedn);
            }
            basedn = strdup(optarg);
            break;
        case 'n': /* number of entries to add */
            entrynum = atoi(optarg);
            break;
        case 'I': /* interval to measure the time gap */
            interval = atoi(optarg);
            break;
        case 's': /* nano second to wait between 2 adds */
            nanosec = atoi(optarg);
            break;
        case 't': /* threads */
            threads = atoi(optarg);
            break;
        case 'e': /* uid prefix */
            uidprefix = strdup(optarg);
            break;
        case 'a': /* asynchronous add */
            synchronous = 0;
            break;
        case 'v': /* verbose */
            verbose = 1;
            break;
        default:
            usage(me);
            break;
        }
    }

    if (NULL == masterhost) {
        fprintf(stderr, "main: no master host\n");
        usage(me);
    }
    if (0 >= masterport) {
        fprintf(stderr, "main: invalid master port\n");
        usage(me);
    }
    if (NULL == replicahost) {
        fprintf(stderr, "main: no replica host\n");
        usage(me);
    }
    if (0 >= replicaport) {
        fprintf(stderr, "main: invalid replica port\n");
        usage(me);
    }
    if (NULL == masterbdn) {
        fprintf(stderr, "main: no master bind dn\n");
        usage(me);
    }
    if (NULL == replicabpw) {
        fprintf(stderr, "main: no replica bind password\n");
        usage(me);
    }
    if (NULL == replicabdn) {
        fprintf(stderr, "main: no replica bind dn\n");
        usage(me);
    }
    if (NULL == masterbpw) {
        fprintf(stderr, "main: no master bind password\n");
        usage(me);
    }
    if (NULL == basedn) {
        fprintf(stderr, "main: no replication suffix\n");
        usage(me);
    }
    if (0 >= entrynum) {
        fprintf(stderr, "main: invalid number of entries to add\n");
        usage(me);
    }
    if (0 >= interval || interval > entrynum) {
        fprintf(stderr,
                "main: invalid interval (1 <= interval <= %d)\n", entrynum);
        usage(me);
    }
    if (0 > nanosec) {
        fprintf(stderr, "main: invalid nanosec\n");
        usage(me);
    }
    if (0 >= threads) {
        fprintf(stderr, "main: invalid thread count\n");
        usage(me);
    }
    if (NULL == uidprefix) {
        uidprefix = strdup("user");
        if (NULL == uidprefix) {
            fprintf(stderr, "main: invalid uid prefix\n");
            usage(me);
        }
    }

    /* check master & replica are available */
    rc = check_servers();
    if (rc) {
        exit(1);
    }

    perfitemlen = entrynum / interval + ((entrynum % interval) ? 1 : 0);
    totalperfitemlen = perfitemlen * threads;
    perfitems = (perfItem *)malloc(sizeof(perfItem) * totalperfitemlen);
    if (NULL == perfitems) {
        perror("malloc");
        fprintf(stderr, "main: failed to allocate perfitem array\n");
        exit(1);
    }
    for (i = 0, pip = perfitems; i < totalperfitemlen; i++, pip++) {
        pip->id = UNUSED;
    }

    /* start master threads */
    mthread_args = 
        (struct thread_arg *)malloc(sizeof(struct thread_arg) * threads);
    if (NULL == mthread_args) {
        perror("malloc");
        fprintf(stderr, "main: failed to allocate mthread_args array\n");
        exit(1);
    }
    mthreads = (pthread_t *)malloc(sizeof(pthread_t) * threads);
    if (NULL == mthreads) {
        perror("malloc");
        fprintf(stderr, "main: failed to allocate mthreads array\n");
        exit(1);
    }
    for (i = 0; i < threads; i++) {
        (mthread_args+i)->threadid = i;
        rc = pthread_create(mthreads+i, NULL, master_thread, mthread_args+i);
        if (rc) {
            perror("pthread_create");
            fprintf(stderr, "main: failed to start master thread(%d): %d\n",
                    i, rc);
            exit(1);
        }
    }

    /* start replica thread */
    rthread_args = 
        (struct thread_arg *)malloc(sizeof(struct thread_arg) * threads);
    if (NULL == rthread_args) {
        perror("malloc");
        fprintf(stderr, "main: failed to allocate rthread_args array\n");
        exit(1);
    }
    rthreads = (pthread_t *)malloc(sizeof(pthread_t) * threads);
    if (NULL == rthreads) {
        perror("malloc");
        fprintf(stderr, "main: failed to allocate rthreads array\n");
        exit(1);
    }
    for (i = 0; i < threads; i++) {
        (rthread_args+i)->threadid = i;
        rc = pthread_create(rthreads+i, NULL, replica_thread, rthread_args+i);
        if (rc) {
            perror("pthread_create");
            fprintf(stderr, "main: failed to start replica thread(%d): %d\n",
                    i, rc);
            exit(1);
        }
    }

    for (i = 0; i < threads; i++) {
        pthread_join(*(mthreads+i), NULL);
        pthread_join(*(rthreads+i), NULL);
    }

    print_stats();
    if (masterhost) {
        free(masterhost);
    }
    if (replicahost) {
        free(replicahost);
    }
    if (mthread_args) {
        free(mthread_args);
    }
    if (mthreads) {
        free(mthreads);
    }
    if (rthread_args) {
        free(rthread_args);
    }
    if (rthreads) {
        free(rthreads);
    }
    if (perfitems) {
        free(perfitems);
    }
    if (uidprefix) {
        free(uidprefix);
    }
    exit(0);
}

/* helper functions */
static void
usage(char *me)
{
    fprintf(stdout,
            "%s -h <masterhost> -p <masterport>\n"
            "        -i <replicahost> -q <replicaport>\n" 
            "        -D <masterbdn> -w <masterbpw>\n"
            "        -d <replicabdn> -W <replicabpw>\n"
            "        -n <number_of_entries> -I <interval_to_measure>\n"
            "        -b <basedn> -s <nanosec> -t <threads>\n"
            "        -e <uid_prefix> -a -v\n", me);
    fprintf(stdout,
            "        <nanosec>: nano seconds to wait b/w 2 adds\n"
            "        <uid_prefix>: uid=<uid_prefix>.<thread>.<seqnum>\n"
            "        -a: asynchronous add\n"
            "        -v: verbose\n");
    exit(1);
}

/*
 * init_ldap: initialize ldap; bind to the server.
 */
static int
init_ldap(char *host, int port, LDAP **ld, char *binddn, char *bindpw)
{
    int rc = 0;
    char *ldapurl = NULL;
    struct berval bv = {0, NULL};

    rc = asprintf(&ldapurl, "ldap://%s:%d", host, port);
    if ((rc < 0) || (NULL == ldapurl)) {
        perror("asprintf");
        fprintf(stderr,
                "init_ldap: failed to generate ldapurl \"ldap://%s:%d\"\n",
                host, port);
        if (0 == rc) {
            rc = -1;
        }
        goto bail;
    }

    rc = ldap_initialize(ld, ldapurl);
    if (rc) {
        fprintf(stderr,
                "init_ldap: failed to initialize ldap://%s:%d: %s (%d)\n",
                host, port, ldap_err2string(rc), rc);
        goto bail;
    }

    bv.bv_val = bindpw;
    bv.bv_len = bindpw ? strlen(bindpw) : 0;
    rc = ldap_sasl_bind_s(*ld, binddn, LDAP_SASL_SIMPLE, &bv, NULL, NULL, NULL);
    if (rc) {
        fprintf(stderr,
                "init_ldap: failed to bind ldap://%s:%d: %s (%d)\n",
                host, port, ldap_err2string(rc), rc);
        goto bail;
    }

bail:
    if (ldapurl) {
        free(ldapurl);
    }
    return rc;
}

/*
 * cleanup_ldap
 */
static int
cleanup_ldap(LDAP *ld)
{
    int rc = 0;
    if (ld) {
#if 0
        rc = ldap_unbind_ext(ld, NULL, NULL);
        if (rc) {
            fprintf(stderr, "cleanup_ldap: failed to unbind: %s (%d)\n",
                    ldap_err2string(rc), rc);
            goto bail;
        }
#else
        rc = ldap_destroy(ld);
        if (rc) {
            fprintf(stderr, "cleanup_ldap: failed to destroy: %s (%d)\n",
                    ldap_err2string(rc), rc);
            goto bail;
        }
#endif
    }

bail:
    return rc;
}

static void
cleanup_mod(LDAPMod **mod, int num)
{
    int i;

    if (NULL == mod) {
        fprintf(stderr, "cleanup_mod: NULL mod\n");
        return;
    }
    if (0 == num) {
        fprintf(stderr, "cleanup_mod: val count is 0\n");
        return;
    }
    for (i = 0; i < num && (*mod)->mod_values[i]; i++) {
        free((*mod)->mod_values[i]);
    }
    if ((*mod)->mod_values) {
        free((*mod)->mod_values);
    }
    if ((*mod)->mod_type) {
        free((*mod)->mod_type);
    }
    if (*mod) {
        free(*mod);
    }
    *mod = NULL;
    return;
}

/*
 * e.g.,
 * "objectclass", {"top", "person", "organizationalperson", "inetorgperson"}, 4
 */
static int
set_attr_values(LDAPMod **mod, char *type, char **vals, int num)
{
    int rc = -1;
    int i;
    if (NULL == mod) {
        fprintf(stderr, "set_attr_values: NULL mod\n");
        return rc;
    }
    if (NULL == vals) {
        fprintf(stderr, "set_attr_values: no vals\n");
        return rc;
    }
    if (0 == num) {
        fprintf(stderr, "set_attr_values: val count is 0\n");
        return rc;
    }
    *mod = (LDAPMod *)malloc(sizeof(LDAPMod));
    if (NULL == *mod) {
        perror("malloc");
        fprintf(stderr, "set_attr_values: "
                "failed allocate LDAPMod for %s\n", type);
        goto bail;
    }
    (*mod)->mod_op = LDAP_MOD_ADD;
    rc = asprintf(&((*mod)->mod_type), type);
    if ((rc < 0) || (NULL == (*mod)->mod_type)) {
        perror("asprintf");
        fprintf(stderr, "set_attr_values: "
                "failed set type %s to LDAPMod\n", type);
        goto bail;
    }
    (*mod)->mod_values = (char **)calloc(sizeof(char *), num + 1);
    for (i = 0; i < num; i++) {
        rc = asprintf(&((*mod)->mod_values[i]), vals[i]);
        if ((rc < 0) || (NULL == (*mod)->mod_values[i])) {
            perror("asprintf");
            fprintf(stderr, "set_attr_values: "
                    "failed set value %s to LDAPMod\n", vals[i]);
            goto bail;
        }
    }
    (*mod)->mod_values[num] = NULL;
    return 0; /* success */
bail:
    cleanup_mod(mod, num);
    return rc;
}

static int
init_template_entry(LDAPMod ***attrs)
{
    int rc = -1;
    int len = 10; /* 6 used for now. */
    char *values[10];
    int i;

    *attrs = calloc(sizeof(LDAPMod *), len);
    if (NULL == *attrs) {
        perror("calloc");
        fprintf(stderr, "init_template_entry: "
                "failed allocate LDAPMod * for attrs\n");
        goto bail;
    }
    /* attrs[0]: objectclass */
    values[0] = "top";
    values[1] = "person";
    values[2] = "organizationalperson";
    values[3] = "inetorgperson";
    values[4] = NULL;
    rc = set_attr_values(&((*attrs)[0]), "objectclass", values, 4);
    if ((rc < 0) || (NULL == (*attrs)[0])) {
        fprintf(stderr,
                "init_template_entry: failed set objectclass to LDAPMod\n");
        goto bail;
    }

    /* (*attrs)[1]: cn */
    values[0] = "cn value";
    values[1] = NULL;
    rc = set_attr_values(&((*attrs)[1]), "cn", values, 1);
    if ((rc < 0) || (NULL == (*attrs)[1])) {
        fprintf(stderr, "init_template_entry: failed set cn to LDAPMod\n");
        goto bail;
    }

    /* (*attrs)[2]: sn */
    values[0] = "sn value";
    values[1] = NULL;
    rc = set_attr_values(&((*attrs)[2]), "sn", values, 1);
    if ((rc < 0) || (NULL == (*attrs)[2])) {
        fprintf(stderr, "init_template_entry: failed set sn to LDAPMod\n");
        goto bail;
    }

    /* (*attrs)[3]: givenname */
    values[0] = "givenname value";
    values[1] = NULL;
    rc = set_attr_values(&((*attrs)[3]), "givenname", values, 1);
    if ((rc < 0) || (NULL == (*attrs)[3])) {
        fprintf(stderr, 
                "init_template_entry: failed set givenname to LDAPMod\n");
        goto bail;
    }

    /* (*attrs)[4]: mail */
    values[0] = "mail value";
    values[1] = NULL;
    rc = set_attr_values(&((*attrs)[4]), "mail", values, 1);
    if ((rc < 0) || (NULL == (*attrs)[4])) {
        fprintf(stderr, "init_template_entry: failed set mail to LDAPMod\n");
        goto bail;
    }

    /* (*attrs)[5]: userpassword */
    values[0] = "mail value";
    values[1] = NULL;
    rc = set_attr_values(&((*attrs)[5]), "userpassword", values, 1);
    if ((rc < 0) || (NULL == (*attrs)[5])) {
        fprintf(stderr, 
                "init_template_entry: failed set userpassword to LDAPMod\n");
        goto bail;
    }
#if 0
    /* (*attrs)[6]: uid */
    values[0] = "uid value";
    values[1] = NULL;
    rc = set_attr_values(&((*attrs)[6]), "uid", values, 1);
    if ((rc < 0) || (NULL == (*attrs)[6])) {
        fprintf(stderr, "init_template_entry: failed set uid to LDAPMod\n");
        goto bail;
    }
#endif
    return rc;

bail:
    if (attrs) {
        for (i = 0; i < len && (*attrs)[i]; i++) {
            cleanup_mod(&((*attrs)[i]), 4); /* num 4 for objectclass is the largest */
        }
        free(attrs);
    }
    return rc;
}

/*
 * master thread:
 * add entries; start timer
 */
static void *
master_thread(void *ptr)
{
    unsigned int id = 0;
    perfItem *pip = NULL;
    LDAP *ld = NULL;
    LDAPMod **attrs = NULL;
    LDAPMod **ap = NULL;
    unsigned int currid = 0;
    int rc;
    char dn[BUFSIZ];
    struct timespec nanoreq;
    struct thread_arg *myarg = (struct thread_arg *)ptr;
    perfItem *myperfitems = NULL;
    int msgid = -1;
    LDAPMessage *res;
    struct timeval timeout = {0};

    if (NULL == myarg) {
        fprintf(stderr, "master_thread: no arg\n");
        goto bail;
    }

    if (myarg->threadid < 0 || myarg->threadid >= threads) {
        fprintf(stderr, "master_thread: invalid thread id: %d "
                        "(supposed to be in [0..%d])\n",
                        myarg->threadid, threads-1);
        goto bail;
    }

    myperfitems = perfitems + (myarg->threadid * perfitemlen);

    rc = init_ldap(masterhost, masterport, &ld, masterbdn, masterbpw);
    if (rc) {
        fprintf(stderr, "master_thread: init_ldap returned (%d)\n", rc);
        goto bail;
    }

    rc = init_template_entry(&attrs);
    if (rc) {
        fprintf(stderr,
                "master_thread: init_template_entry returned (%d)\n", rc);
        goto bail;
    }

    nanoreq.tv_sec = 0;
    nanoreq.tv_nsec = nanosec;

    if (synchronous) {
        timeout.tv_sec = -1; /* the select blocks indefinitely. */
    }

    for (currid = 0; currid < entrynum; currid++) {
        snprintf(dn, BUFSIZ, "uid=%s.%d.%u,%s",
                 uidprefix, myarg->threadid, currid, basedn);
        rc = ldap_add_ext(ld, dn, attrs, NULL, NULL, &msgid);
        if (rc) {
            fprintf(stderr, "master_thread(id %d): ldap_add_ext(%d): %s (%d)\n",
                    currid, msgid, ldap_err2string(rc), rc);
            goto bail;
        }
        if (synchronous) {
            rc = ldap_result(ld, msgid, 0/* MSG_ONE*/, &timeout, &res);
            switch (rc) {
            case -1:
                fprintf(stderr,
                        "master_thread(id %d):ldap_result(%d): %s (%d)\n",
                        currid, msgid, ldap_err2string(rc), rc);
                goto bail;
            default:
                ldap_parse_result(ld, res, &rc, NULL, NULL, NULL, NULL, 1);
                if (rc) {
                    fprintf(stderr,
                            "master_thread(id %d):ldap_parse_result(%d): %s (%d)\n",
                            currid, msgid, ldap_err2string(rc), rc);
                    goto bail;
                }
            case 0:
                break; /* timed out; just ignore */
            }
        }
        if (0 == (currid % interval)) {
            id = currid / interval;
            pip = myperfitems + id;
            gettimeofday(&(pip->start), NULL);
            pip->id = currid;
            if (verbose) {
                fprintf(stderr, "master_thread[%d]: perfitems[%d]: id=%d\n",
                        myarg->threadid, id, currid);
            }
        }
        if (nanosec) {
            nanosleep(&nanoreq, NULL);
        }
    }
bail:
    myarg->rc  = rc;
    if (!synchronous) {
        int rcnt = entrynum;
        nanoreq.tv_sec = 0;
        nanoreq.tv_nsec = 1000;
        timeout.tv_sec = -1; /* the select blocks indefinitely. */
        while (rcnt > 0) {
            rc = ldap_result(ld, LDAP_RES_ANY, 0/* MSG_ONE */, &timeout, &res);
            if (rc > 0) {
                rcnt--;
            }
            ldap_msgfree(res);
            nanosleep(&nanoreq, NULL);
        }
    }
    cleanup_ldap(ld);
    for (ap = attrs; ap && *ap; ap++) {
        cleanup_mod(ap, 4); /* num 4 for objectclass is the largest */
    }
    if (attrs) {
        free(attrs);
    }
    return NULL;
}

/*
 * replca thread:
 * read entries; stop timer for the entry
 */
static void *
replica_thread(void *ptr)
{
    LDAP *ld = NULL;
    perfItem *pip = NULL;
    int rc;
    char dn[BUFSIZ];
    unsigned int i = 0;
    char *attrs[2];
    struct timeval timeout;
    LDAPMessage *res = NULL;
    struct timespec nanoreq;
    struct thread_arg *myarg = (struct thread_arg *)ptr;
    perfItem *myperfitems = NULL;

    if (NULL == myarg) {
        fprintf(stderr, "replica_thread: no arg\n");
        goto bail;
    }

    if (myarg->threadid < 0 || myarg->threadid >= threads) {
        fprintf(stderr, "replica_thread: invalid thread id: %d "
                        "(supposed to be in [0..%d])\n",
                        myarg->threadid, threads-1);
        goto bail;
    }

    myperfitems = perfitems + (myarg->threadid * perfitemlen);

    rc = init_ldap(replicahost, replicaport, &ld, replicabdn, replicabpw);
    if (rc) {
        fprintf(stderr, "replica_thread: init_ldap returned (%d)\n", rc);
        goto bail;
    }

    attrs[0] = "uid";
    attrs[1] = NULL;

    timeout.tv_sec = 1;
    timeout.tv_usec = 0;

    nanoreq.tv_sec = 0;
    nanoreq.tv_nsec = 5;

    for (i = 0, pip = myperfitems; i < perfitemlen; i++, pip++) {
        while (UNUSED == pip->id) {
            nanosleep(&nanoreq, NULL);
        }
        if (verbose) {
            fprintf(stderr, "replica_thread[%d]: perfitems[%d]: id=%d\n",
                    myarg->threadid, i, pip->id);
        }
        snprintf(dn, BUFSIZ, "uid=%s.%d.%u,%s",
                 uidprefix, myarg->threadid, pip->id, basedn);
        do {
            rc = ldap_search_ext_s(ld, dn, LDAP_SCOPE_BASE, "(objectclass=*)",
                               attrs, 0, NULL, NULL, &timeout, -1, &res);
            ldap_msgfree(res);
            if (LDAP_SUCCESS == rc) {
                gettimeofday(&(pip->end), NULL);
                break;
            }
            if ((LDAP_NO_SUCH_OBJECT == rc) || (LDAP_TIMEOUT == rc) ||
                 (LDAP_CONNECT_ERROR == rc)) {
                continue;
            } else {
                fprintf(stderr,
                        "replica_thread(id %d): ldap_search_ext_s: %s (%d)\n",
                        pip->id, ldap_err2string(rc), rc);
                goto bail;
            }
        } while (1);
    }
bail:
    myarg->rc  = rc;
    cleanup_ldap(ld);
    return NULL;
}

static int
check_servers()
{
    LDAP *ld = NULL;
    int rc;
    rc = init_ldap(masterhost, masterport, &ld, masterbdn, masterbpw);
    if (rc) {
        fprintf(stderr, "check_servers: master is not available (%d)\n", rc);
        return rc;
    }
    cleanup_ldap(ld);
    rc = init_ldap(replicahost, replicaport, &ld, replicabdn, replicabpw);
    if (rc) {
        fprintf(stderr, "check_servers: replica is not available (%d)\n", rc);
    }
    return rc;
}

static int
perfcomp(const void *p0, const void *p1)
{
    perfItem *pip0 = (perfItem *)p0;
    perfItem *pip1 = (perfItem *)p1;
    int delta = 0;
    if (NULL == pip0) {
        if (NULL == pip1) {
            return 0;
        } else {
            return -1;
        }
    } else {
        if (NULL == pip1) {
            return 1;
        } else {
            delta = pip0->delta.tv_sec - pip1->delta.tv_sec;
            if (delta) {
                return delta;
            } else {
                return pip0->delta.tv_usec - pip1->delta.tv_usec;
            }
        }
    }
}

static int
print_stats()
{
    perfItem *pip = NULL;
    int i;
    int rc = 0;
    int usec;
    unsigned long long avgdeltasec;
    unsigned long long avgdeltausec;
    double tmpd;
    double avg;
    double variance;
    double deviation;
    int tid;

    if (NULL == perfitems) {
           fprintf(stdout, "[EMPTY RESULT]\n");
        return rc;
    }

    avgdeltasec = 0;
    avgdeltausec = 0;
    if (verbose) {
        fprintf(stdout, "[ORIGINAL RESULT]\n");
    }
    tid = -1;
    for (i = 0, pip = perfitems; i < totalperfitemlen ; i++, pip++) {
        if (0 == i % perfitemlen) {
            tid++;
        }
        avgdeltasec += pip->delta.tv_sec = pip->end.tv_sec - pip->start.tv_sec;
        usec = pip->end.tv_usec - pip->start.tv_usec;
        if (usec < 0) {
            pip->delta.tv_sec -= 1;
            pip->delta.tv_usec = usec + 1000000;
        } else {
            pip->delta.tv_usec = pip->end.tv_usec - pip->start.tv_usec;
        }    
        avgdeltausec += pip->delta.tv_usec;
        if (verbose) {
            fprintf(stdout, 
                    "%d:%d: start: %lu.%lu --> end: %lu.%lu; delta: %lu.%lu\n",
                    tid,
                    pip->id, pip->start.tv_sec, pip->start.tv_usec,
                    pip->end.tv_sec, pip->end.tv_usec,
                    pip->delta.tv_sec, pip->delta.tv_usec);
        }
    }
    qsort(perfitems, totalperfitemlen, sizeof(perfItem), perfcomp);
    if (verbose) {
        fprintf(stdout, "[SORTED RESULT]\n");
        tid = -1;
        for (i = 0, pip = perfitems; i < totalperfitemlen ; i++, pip++) {
            if (0 == i % perfitemlen) {
                tid++;
            }
            fprintf(stdout, 
                    "%d:%d: start: %lu.%lu --> end: %lu.%lu; delta: %lu.%lu\n",
                    tid, pip->id, pip->start.tv_sec, pip->start.tv_usec,
                    pip->end.tv_sec, pip->end.tv_usec,
                    pip->delta.tv_sec, pip->delta.tv_usec);
        }
    }
    /* median */
    i = totalperfitemlen / 2;
    fprintf(stdout, "Median duration: ID[%d]: %lu.%lu (sec)\n",
            (perfitems+i)->id,
            (perfitems+i)->delta.tv_sec, (perfitems+i)->delta.tv_usec);

    /* average */
    avgdeltasec /= totalperfitemlen;
    avgdeltausec /= totalperfitemlen;
    fprintf(stdout, "Average duration: %llu.%llu (sec)\n",
            avgdeltasec, avgdeltausec);

    /* standard deviation */
    avg = (double)avgdeltasec + (double)avgdeltausec / 1000000;
    variance = 0;
    for (i = 0, pip = perfitems; i < totalperfitemlen ; i++, pip++) {
        tmpd = (double)pip->delta.tv_sec + (double)pip->delta.tv_usec/1000000;
        tmpd -= avg;
        variance += tmpd * tmpd;
    }
    variance /= totalperfitemlen;
    deviation = sqrt(variance);
    fprintf(stdout, "Deviation: %f\n", deviation);
    
    return rc;
}
