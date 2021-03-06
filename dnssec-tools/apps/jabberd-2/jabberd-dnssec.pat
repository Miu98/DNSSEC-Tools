Index: configure.in
===================================================================
RCS file: /home/cvs/jabberd2/configure.in,v
retrieving revision 1.95
diff -u -p -r1.95 configure.in
--- configure.in	21 Aug 2005 10:06:06 -0000	1.95
+++ configure.in	1 Mar 2007 15:28:33 -0000
@@ -63,6 +63,10 @@ for libpath in $split_libs ; do
     LDFLAGS="-L$libpath $LDFLAGS"
 done
 
+# Check whether user wants DNSSEC local validation support
+AC_ARG_WITH(dnssec-local-validation,
+        [  --with-dnssec-local-validation Enable local DNSSEC validation using libval (no)], want_dnssec=$enableval, want_dnssec=no)
+
 dnl
 dnl header checks
 dnl
@@ -132,7 +136,39 @@ if test "$ac_cv_lib_nsl_gethostbyname" =
 fi
 
 dnl res_query has been seen in libc, libbind and libresolv
-if test "x-$ac_cv_header_resolv_h" = "x-yes" ; then
+if ! test "x-$want-dnssec" = "x-no" ; then
+dnl    if test "x$withval" != "xyes" ; then
+dnl        CPPFLAGS="$CPPFLAGS -I${withval}"
+dnl        LDFLAGS="$LDFLAGS -L${withval}"
+dnl        if test ! -z "$need_dash_r" ; then
+dnl            LDFLAGS="$LDFLAGS -R${withval}"
+dnl        fi
+dnl        if test ! -z "$blibpath" ; then
+dnl            blibpath="$blibpath:${withval}"
+dnl        fi
+dnl    fi
+    AC_CHECK_HEADERS(validator/validator.h)
+    if test "$ac_cv_header_validator_validator_h" != yes; then
+        AC_MSG_ERROR(Can't find validator.h)
+    fi
+    AC_CHECK_LIB(ssl, SHA1_Init)
+    AC_CHECK_LIB(sres, query_send)
+    if test "$ac_cv_lib_sres_query_send" != yes; then
+        AC_MSG_ERROR(Can't find libsres)
+    fi
+    AC_CHECK_LIB(val, p_val_status,
+                 LIBS="$LIBS -lval"
+                 have_val_res_query=yes,
+                 [ AC_CHECK_LIB(pthread, pthread_rwlock_init)
+		   AC_CHECK_LIB(val-threads, p_val_status,
+                   have_val_res_query=yes
+                   LIBS="$LIBS -lval-threads -lpthread"
+                   LIBVAL_SUFFIX="-threads",
+                   AC_MSG_ERROR(Can't find libval or libval-threads))
+                 ])
+    AC_DEFINE(DNSSEC_LOCAL_VALIDATION, 1,
+              [Define if you want local DNSSEC validation support])
+elif test "x-$ac_cv_header_resolv_h" = "x-yes" ; then
     AC_CHECK_FUNCS(res_query)
     if test "x-$ac_cv_func_res_query" = "x-yes" ; then
         have_res_query=yes
@@ -174,7 +210,9 @@ if test "x-$ac_cv_header_windns_h" = "x-
                     LIBS="$save_libs"])
 fi
 
-if test "x-$have_res_query" = "x-yes" ; then
+if test "x-$have_val_res_query" = "x-yes" ; then
+    AC_DEFINE(HAVE_VAL_RES_QUERY,1,[Define to 1 if you have the 'val_res_query' function.])
+elif test "x-$have_res_query" = "x-yes" ; then
     AC_DEFINE(HAVE_RES_QUERY,1,[Define to 1 if you have the 'res_query' function.])
 elif test "x-$have_dnsquery" = "x-yes" ; then
     AC_DEFINE(HAVE_DNSQUERY,1,[Define to 1 if you have the 'DnsQuery' function.])
Index: etc/resolver.xml.dist.in
===================================================================
RCS file: /home/cvs/jabberd2/etc/resolver.xml.dist.in,v
retrieving revision 1.12
diff -u -p -r1.12 resolver.xml.dist.in
--- etc/resolver.xml.dist.in	29 Oct 2003 23:30:06 -0000	1.12
+++ etc/resolver.xml.dist.in	1 Mar 2007 15:28:34 -0000
@@ -78,4 +78,14 @@
   <ipv6/>
   -->
 
+  <dnssec>
+    <!-- Log level for DNSSEC validation. -->
+    <log_level>5<log_level/>
+
+    <!-- If this is enabled, the resolver drop untrusted DNS responses. -->
+    <!--
+    <drop_untrusted/>
+    -->
+  </dnssec>
+
 </resolver>
Index: resolver/dns.c
===================================================================
RCS file: /home/cvs/jabberd2/resolver/dns.c,v
retrieving revision 1.8
diff -u -p -r1.8 dns.c
--- resolver/dns.c	15 Dec 2004 11:09:13 -0000	1.8
+++ resolver/dns.c	1 Mar 2007 15:28:34 -0000
@@ -48,6 +48,9 @@
 #ifdef HAVE_WINDNS_H
 # include <windns.h>
 #endif
+#ifdef DNSSEC_LOCAL_VALIDATION
+# include <validator/validator.h>
+#endif
 
 
 /* compare two srv structures, order by priority then by randomised weight */
@@ -72,7 +75,7 @@ static int _srv_compare(const void *a, c
 
 
 /* unix implementation */
-#ifdef HAVE_RES_QUERY
+#if defined(HAVE_RES_QUERY) || defined(HAVE_VAL_RES_QUERY)
 
 /* older systems might not have these */
 #ifndef T_SRV
@@ -156,13 +159,16 @@ static void *_srv_rr(dns_packet_t packet
 }
 
 /** the actual resolver function */
-dns_host_t dns_resolve(const char *zone, int query_type) {
+dns_host_t dns_resolve(const char *zone, int query_type, resolver_t r) {
     char host[256];
     dns_packet_t packet;
     int len, qdcount, ancount, an, n;
     unsigned char *eom, *scan;
     dns_host_t *reply, first;
     unsigned int t_type, type, class, ttl;
+#ifdef DNSSEC_LOCAL_VALIDATION
+    val_status_t val_status;
+#endif
 
     if(zone == NULL || *zone == '\0')
         return NULL;
@@ -186,8 +192,37 @@ dns_host_t dns_resolve(const char *zone,
     }
 
     /* do the actual query */
+/* xxx-rks */
+#ifndef DNSSEC_LOCAL_VALIDATION
     if((len = res_query(zone, C_IN, t_type, packet.buf, MAX_PACKET)) == -1 || len < sizeof(HEADER))
         return NULL;
+#else
+    len = val_res_query(NULL, zone, C_IN, t_type,
+                        packet.buf, MAX_PACKET, &val_status);
+
+    /** val_status not set for internal errors */
+    if ((len == -1) && (NETDB_INTERNAL == h_errno)) {
+        log_write(r->log, LOG_NOTICE, "internal err resolving %s",zone);
+        return NULL;
+    }
+    
+    /** log validation status */
+    log_write(r->log, LOG_DEBUG, "ValStatus: %strusted:%s",
+              val_istrusted(val_status) ? "" : "not",
+              p_val_status(val_status));
+    
+    if(len == -1) {
+        return NULL;
+    } else if (r->drop_untrusted && !val_istrusted(val_status)) {
+        log_write(r->log, LOG_NOTICE, "dropping untrusted response for %s",zone);
+        return NULL;
+    } else if ((len < sizeof(HEADER)) || (len > MAX_PACKET)) {
+        log_write(r->log, LOG_NOTICE, "packet size err resolving %s",zone);
+        return NULL;
+    }
+    
+#endif /* DNSSEC_LOCAL_VALIDATION */
+
 
     /* we got a valid result, containing two types of records - packet
      * and answer .. we have to skip over the packet records */
@@ -246,6 +281,9 @@ dns_host_t dns_resolve(const char *zone,
         reply[an]->type = type;
         reply[an]->class = class;
         reply[an]->ttl = ttl;
+#ifdef DNSSEC_LOCAL_VALIDATION
+        reply[an]->val_status = val_status;
+#endif
 
         reply[an]->next = NULL;
 
Index: resolver/dns.h
===================================================================
RCS file: /home/cvs/jabberd2/resolver/dns.h,v
retrieving revision 1.6
diff -u -p -r1.6 dns.h
--- resolver/dns.h	26 Apr 2004 05:05:47 -0000	1.6
+++ resolver/dns.h	1 Mar 2007 15:28:34 -0000
@@ -37,6 +37,9 @@ typedef struct dns_host_st {
     unsigned int        ttl;
 
     void                *rr;
+#ifdef DNSSEC_LOCAL_VALIDATION
+    unsigned int        val_status;
+#endif
 } *dns_host_t;
 
 typedef struct dns_srv_st {
@@ -48,7 +51,9 @@ typedef struct dns_srv_st {
     char                name[256];
 } *dns_srv_t;
 
-extern dns_host_t   dns_resolve(const char *zone, int type);
+struct resolver_st;
+
+extern dns_host_t   dns_resolve(const char *zone, int type, struct resolver_st *r);
 extern void         dns_free(dns_host_t dns);
 
 #endif
Index: resolver/resolver.c
===================================================================
RCS file: /home/cvs/jabberd2/resolver/resolver.c,v
retrieving revision 1.50
diff -u -p -r1.50 resolver.c
--- resolver/resolver.c	8 Aug 2005 02:15:17 -0000	1.50
+++ resolver/resolver.c	1 Mar 2007 15:28:35 -0000
@@ -20,6 +20,24 @@
 
 #include "resolver.h"
 
+#ifdef DNSSEC_LOCAL_VALIDATION
+# include <validator/validator.h>
+
+//     typedef void    (*val_log_cb_t) (struct val_log *logp, int level,
+//                                      const char *buf);
+
+void _resolver_log(struct val_log *logp, int level, const char *str)
+{
+    resolver_t r;
+
+    if ((NULL == logp) || (NULL == str))
+        return;
+
+    r = (resolver_t) logp->a_void;
+    log_write(r->log, LOG_NOTICE, str);
+}
+#endif
+
 static sig_atomic_t resolver_shutdown = 0;
 static sig_atomic_t resolver_lost_router = 0;
 static sig_atomic_t resolver_logrotate = 0;
@@ -116,6 +134,11 @@ static void _resolver_config_expand(reso
     }
 
     r->resolve_aaaa = config_count(r->config, "ipv6") ? 1 : 0;
+
+#ifdef DNSSEC_LOCAL_VALIDATION
+    r->drop_untrusted = config_count(r->config, "dnssec.drop_untrusted") ? 1 : 0;
+    r->dnssec_log_level = j_atoi(config_get_one(r->config, "dnssec.log_level", 0), 5347);
+#endif
 }
 
 static int _resolver_sx_callback(sx_t s, sx_event_t e, void *data, void *arg) {
@@ -323,17 +346,28 @@ static int _resolver_sx_callback(sx_t s,
 
                 log_debug(ZONE, "trying srv lookup for %s", zone);
             
-                srvs = dns_resolve(zone, DNS_QUERY_TYPE_SRV);
+                srvs = dns_resolve(zone, DNS_QUERY_TYPE_SRV, r);
 
                 if(srvs != NULL) {
                     /* resolve to A records */
                     for(srvscan = srvs; srvscan != NULL; srvscan = srvscan->next) {
                         log_debug(ZONE, "%s has srv %s, doing A lookup", zone, ((dns_srv_t) srvscan->rr)->name);
 
-                        as = dns_resolve(((dns_srv_t) srvscan->rr)->name, DNS_QUERY_TYPE_A);
+                        as = dns_resolve(((dns_srv_t) srvscan->rr)->name, DNS_QUERY_TYPE_A, r);
 
                         for(ascan = as; ascan != NULL; ascan = ascan->next) {
-                            log_write(r->log, LOG_NOTICE, "[%s] resolved to %s:%d (%d seconds to live)", zone, (char *) ascan->rr, ((dns_srv_t) srvscan->rr)->port, ascan->ttl);
+                            log_write(r->log, LOG_NOTICE,
+#ifdef DNSSEC_LOCAL_VALIDATION
+                                      "[%s] resolved to %s:%d (%d seconds to live; %strusted:%s)",
+                                      zone, (char *) ascan->rr,
+                                      ((dns_srv_t) srvscan->rr)->port, ascan->ttl,
+                                      val_istrusted(ascan->val_status) ? "" : "not ",
+                                      p_val_status(ascan->val_status)
+#else
+                                      "[%s] resolved to %s:%d (%d seconds to live)",
+                                      zone, (char *) ascan->rr, ((dns_srv_t) srvscan->rr)->port, ascan->ttl
+#endif
+                                          );
 
                             eip = nad_insert_elem(nad, 1, NAD_ENS(nad, 1), "ip", (char *) ascan->rr);
 
@@ -354,10 +388,22 @@ static int _resolver_sx_callback(sx_t s,
                         for(srvscan = srvs; srvscan != NULL; srvscan = srvscan->next) {
                             log_debug(ZONE, "%s has srv %s, doing AAAA lookup", zone, ((dns_srv_t) srvscan->rr)->name);
 
-                            as = dns_resolve(((dns_srv_t) srvscan->rr)->name, DNS_QUERY_TYPE_AAAA);
+                            as = dns_resolve(((dns_srv_t) srvscan->rr)->name, DNS_QUERY_TYPE_AAAA, r);
 
                             for(ascan = as; ascan != NULL; ascan = ascan->next) {
-                                log_write(r->log, LOG_NOTICE, "[%s] resolved to [%s]:%d (%d seconds to live)", zone, (char *)ascan->rr, ((dns_srv_t) srvscan->rr)->port, ascan->ttl);
+                                log_write(r->log, LOG_NOTICE,
+#ifdef DNSSEC_LOCAL_VALIDATION
+                                          "[%s] resolved to [%s]:%d (%d seconds to live; %strusted:%s)",
+                                          zone, (char *)ascan->rr,
+                                          ((dns_srv_t) srvscan->rr)->port, ascan->ttl,
+                                          val_istrusted(ascan->val_status) ? "" : "not ",
+                                          p_val_status(ascan->val_status)
+#else
+                                          "[%s] resolved to [%s]:%d (%d seconds to live)",
+                                          zone, (char *)ascan->rr,
+                                          ((dns_srv_t) srvscan->rr)->port, ascan->ttl,
+#endif
+                                    );
 
                                 eip = nad_insert_elem(nad, 1, NAD_ENS(nad, 1), "ip", (char *)ascan->rr);
 
@@ -387,10 +433,19 @@ static int _resolver_sx_callback(sx_t s,
                 /* A lookup */
                 log_debug(ZONE, "doing A lookup for %s", zone);
 
-                as = dns_resolve(zone, DNS_QUERY_TYPE_A);
+                as = dns_resolve(zone, DNS_QUERY_TYPE_A, r);
                 for(ascan = as; ascan != NULL; ascan = ascan->next) {
-                    log_write(r->log, LOG_NOTICE, "[%s] resolved to [%s:5269] (%d seconds to live)", zone, (char *) ascan->rr, ascan->ttl);
-
+                    log_write(r->log, LOG_NOTICE,
+#ifdef DNSSEC_LOCAL_VALIDATION
+                              "[%s] resolved to [%s:5269] (%d seconds to live; %strusted:%s)",
+                              zone, (char *) ascan->rr, ascan->ttl,
+                              val_istrusted(ascan->val_status) ? "" : "not ",
+                              p_val_status(ascan->val_status)
+#else
+                              "[%s] resolved to [%s:5269] (%d seconds to live)",
+                              zone, (char *) ascan->rr, ascan->ttl
+#endif
+                        );
                     eip = nad_insert_elem(nad, 1, NAD_ENS(nad, 1), "ip", (char *) ascan->rr);
 
                     nad_set_attr(nad, eip, -1, "port", "5269", 4);
@@ -407,11 +462,20 @@ static int _resolver_sx_callback(sx_t s,
                 if(r->resolve_aaaa) {
                     log_debug(ZONE, "doing AAAA lookup for %s", zone);
 
-                    as = dns_resolve(zone, DNS_QUERY_TYPE_AAAA);
+                    as = dns_resolve(zone, DNS_QUERY_TYPE_AAAA, r);
                     for(ascan = as; ascan != NULL; ascan = ascan->next)
                     {
-                        log_write(r->log, LOG_NOTICE, "[%s] resolved to [%s]:5269 (%d seconds to live)", zone, (char *)ascan->rr, ascan->ttl);
-
+                        log_write(r->log, LOG_NOTICE,
+#ifdef DNSSEC_LOCAL_VALIDATION
+                                  "[%s] resolved to [%s]:5269 (%d seconds to live; %strusted:%s)",
+                                  zone, (char *)ascan->rr, ascan->ttl,
+                                  val_istrusted(ascan->val_status) ? "" : "not ",
+                                  p_val_status(ascan->val_status)
+#else
+                                  "[%s] resolved to [%s]:5269 (%d seconds to live)",
+                                  zone, (char *)ascan->rr, ascan->ttl
+#endif
+                            );
                         eip = nad_insert_elem(nad, 1, NAD_ENS(nad, 1), "ip", (char *)ascan->rr);
 
                         nad_set_attr(nad, eip, -1, "port", "5269", 4);
@@ -596,6 +660,15 @@ int main(int argc, char **argv)
 
     r->sx_env = sx_env_new();
 
+#ifdef DNSSEC_LOCAL_VALIDATION
+    {
+        val_log_t * vallog;
+        vallog = val_log_add_cb(r->dnssec_log_level , &_resolver_log);
+        if (vallog)
+            vallog->a_void = r;
+    }
+#endif
+
 #ifdef HAVE_SSL
     if(r->router_pemfile != NULL) {
         r->sx_ssl = sx_env_plugin(r->sx_env, sx_ssl_init, r->router_pemfile, NULL);
Index: resolver/resolver.h
===================================================================
RCS file: /home/cvs/jabberd2/resolver/resolver.h,v
retrieving revision 1.14
diff -u -p -r1.14 resolver.h
--- resolver/resolver.h	26 Apr 2004 05:05:48 -0000	1.14
+++ resolver/resolver.h	1 Mar 2007 15:28:35 -0000
@@ -88,5 +88,13 @@ typedef struct resolver_st {
 
     /** true if we're currently bound in the router */
     int                 online;
+
+#ifdef DNSSEC_LOCAL_VALIDATION
+    /** DNSSEC library log level    */
+    int                 dnssec_log_level;
+
+    /** DNSSEC policy; true if we want to drop untrusted responses */
+    int                 drop_untrusted;
+#endif
 } *resolver_t;
 
