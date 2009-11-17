diff -I '\$Id: ' -u -r -b -w -p -d --exclude-from=/home/rstory/.rcfiles/diff-ignore --new-file clean/openssh-5.3p1/configure.ac openssh-5.3p1/configure.ac
--- clean/openssh-5.3p1/configure.ac	2009-09-11 00:56:08.000000000 -0400
+++ openssh-5.3p1/configure.ac	2009-10-25 14:52:25.000000000 -0400
@@ -3289,32 +3289,41 @@ AC_ARG_WITH(sectok,
 	]
 )
 
-# Check whether user wants OpenSC support
-OPENSC_CONFIG="no"
-AC_ARG_WITH(opensc,
-	[  --with-opensc[[=PFX]]     Enable smartcard support using OpenSC (optionally in PATH)],
-	[
-	    if test "x$withval" != "xno" ; then
+LIBVAL_MSG="no"
+# Check whether user wants DNSSEC local validation support
+AC_ARG_WITH(local-dnssec-validation,
+	[  --with-local-dnssec-validation Enable local DNSSEC validation using libval],
+	[ if test "x$withval" != "xno" ; then
 		if test "x$withval" != "xyes" ; then
-  			OPENSC_CONFIG=$withval/bin/opensc-config
-		else
-  			AC_PATH_PROG(OPENSC_CONFIG, opensc-config, no)
+			CPPFLAGS="$CPPFLAGS -I${withval}"
+			LDFLAGS="$LDFLAGS -L${withval}"
+			if test ! -z "$need_dash_r" ; then
+				LDFLAGS="$LDFLAGS -R${withval}"
 		fi
-		if test "$OPENSC_CONFIG" != "no"; then
-			LIBOPENSC_CFLAGS=`$OPENSC_CONFIG --cflags`
-			LIBOPENSC_LIBS=`$OPENSC_CONFIG --libs`
-			CPPFLAGS="$CPPFLAGS $LIBOPENSC_CFLAGS"
-			LIBS="$LIBS $LIBOPENSC_LIBS"
-			AC_DEFINE(SMARTCARD)
-			AC_DEFINE(USE_OPENSC, 1,
-				[Define if you want smartcard support
-				using OpenSC])
-			SCARD_MSG="yes, using OpenSC"
+			if test ! -z "$blibpath" ; then
+				blibpath="$blibpath:${withval}"
 		fi
 	    fi
-	]
-)
-
+		AC_CHECK_HEADERS(validator/validator.h)
+		if test "$ac_cv_header_validator_validator_h" != yes; then
+			AC_MSG_ERROR(Can't find validator.h)
+		fi
+		AC_CHECK_LIB(sres, query_send)
+		if test "$ac_cv_lib_sres_query_send" != yes; then
+			AC_MSG_ERROR(Can't find libsres)
+		fi
+		LIBVAL_SUFFIX=""
+		AC_CHECK_LIB(val, p_val_status,LIBS="$LIBS -lval",
+			[ AC_CHECK_LIB(pthread, pthread_rwlock_init)
+			  AC_CHECK_LIB(val-threads, p_val_status,
+				[ LIBS="$LIBS -lval-threads -lpthread"
+				  LIBVAL_SUFFIX="-threads"],
+				AC_MSG_ERROR(Can't find libval or libval-threads))
+			])
+		AC_DEFINE(DNSSEC_LOCAL_VALIDATION, 1,
+			[Define if you want local DNSSEC validation support])
+		LIBVAL_MSG="yes, libval${LIBVAL_SUFFIX}"
+	else
 # Check libraries needed by DNS fingerprint support
 AC_SEARCH_LIBS(getrrsetbyname, resolv,
 	[AC_DEFINE(HAVE_GETRRSETBYNAME, 1,
@@ -3368,6 +3377,35 @@ int main()
 			    [Define if HEADER.ad exists in arpa/nameser.h])],,
 			[#include <arpa/nameser.h>])
 	])
+	 fi]
+)
+
+# Check whether user wants OpenSC support
+OPENSC_CONFIG="no"
+AC_ARG_WITH(opensc,
+	[  --with-opensc[[=PFX]]     Enable smartcard support using OpenSC (optionally in PATH)],
+	[
+	    if test "x$withval" != "xno" ; then
+		if test "x$withval" != "xyes" ; then
+  			OPENSC_CONFIG=$withval/bin/opensc-config
+		else
+  			AC_PATH_PROG(OPENSC_CONFIG, opensc-config, no)
+		fi
+		if test "$OPENSC_CONFIG" != "no"; then
+			LIBOPENSC_CFLAGS=`$OPENSC_CONFIG --cflags`
+			LIBOPENSC_LIBS=`$OPENSC_CONFIG --libs`
+			CPPFLAGS="$CPPFLAGS $LIBOPENSC_CFLAGS"
+			LIBS="$LIBS $LIBOPENSC_LIBS"
+			AC_DEFINE(SMARTCARD)
+			AC_DEFINE(USE_OPENSC, 1,
+				[Define if you want smartcard support
+				using OpenSC])
+			SCARD_MSG="yes, using OpenSC"
+		fi
+	    fi
+	]
+)
+
 
 AC_MSG_CHECKING(if struct __res_state _res is an extern)
 AC_LINK_IFELSE([
@@ -4232,6 +4270,7 @@ echo "              TCP Wrappers support
 echo "              MD5 password support: $MD5_MSG"
 echo "                   libedit support: $LIBEDIT_MSG"
 echo "  Solaris process contract support: $SPC_MSG"
+echo "   Local DNSSEC validation support: $LIBVAL_MSG"
 echo "       IP address in \$DISPLAY hack: $DISPLAY_HACK_MSG"
 echo "           Translate v4 in v6 hack: $IPV4_IN6_HACK_MSG"
 echo "                  BSD Auth support: $BSD_AUTH_MSG"
diff -I '\$Id: ' -u -r -b -w -p -d --exclude-from=/home/rstory/.rcfiles/diff-ignore --new-file clean/openssh-5.3p1/dns.c openssh-5.3p1/dns.c
--- clean/openssh-5.3p1/dns.c	2008-06-12 14:46:45.000000000 -0400
+++ openssh-5.3p1/dns.c	2009-10-25 14:52:25.000000000 -0400
@@ -35,6 +35,10 @@
 #include <stdio.h>
 #include <string.h>
 
+#ifdef DNSSEC_LOCAL_VALIDATION
+# include <validator/validator.h>
+#endif
+
 #include "xmalloc.h"
 #include "key.h"
 #include "dns.h"
@@ -176,13 +180,19 @@ verify_host_key_dns(const char *hostname
 {
 	u_int counter;
 	int result;
-	struct rrsetinfo *fingerprints = NULL;
 
 	u_int8_t hostkey_algorithm;
 	u_int8_t hostkey_digest_type;
 	u_char *hostkey_digest;
 	u_int hostkey_digest_len;
 
+#ifndef DNSSEC_LOCAL_VALIDATION
+	struct rrsetinfo *fingerprints = NULL;
+#else
+	struct val_result_chain *val_res, *val_results = NULL;
+	
+#endif
+
 	u_int8_t dnskey_algorithm;
 	u_int8_t dnskey_digest_type;
 	u_char *dnskey_digest;
@@ -199,6 +209,7 @@ verify_host_key_dns(const char *hostname
 		return -1;
 	}
 
+#ifndef DNSSEC_LOCAL_VALIDATION
 	result = getrrsetbyname(hostname, DNS_RDATACLASS_IN,
 	    DNS_RDATATYPE_SSHFP, 0, &fingerprints);
 	if (result) {
@@ -207,7 +218,7 @@ verify_host_key_dns(const char *hostname
 	}
 
 	if (fingerprints->rri_flags & RRSET_VALIDATED) {
-		*flags |= DNS_VERIFY_SECURE;
+		*flags |= (DNS_VERIFY_SECURE|DNS_VERIFY_TRUSTED);
 		debug("found %d secure fingerprints in DNS",
 		    fingerprints->rri_nrdatas);
 	} else {
@@ -255,6 +266,94 @@ verify_host_key_dns(const char *hostname
 
 	xfree(hostkey_digest); /* from key_fingerprint_raw() */
 	freerrset(fingerprints);
+#else
+
+	result = val_resolve_and_check(NULL, hostname, DNS_RDATACLASS_IN,
+	    DNS_RDATATYPE_SSHFP, 0, &val_results);
+	if (result != VAL_NO_ERROR){
+		verbose("DNS lookup error: %s", p_ac_status(val_results->val_rc_status));
+		return -1;
+	}
+
+	/* Initialize host key parameters */
+	if (!dns_read_key(&hostkey_algorithm, &hostkey_digest_type,
+	    &hostkey_digest, &hostkey_digest_len, hostkey)) {
+		error("Error calculating host key fingerprint.");
+		val_free_result_chain(val_results);
+		return -1;
+	}
+
+	counter = 0;
+	for (val_res = val_results; val_res; val_res = val_res->val_rc_next)  {
+		struct val_rrset_rec *val_rrset;
+		struct val_rr_rec *rr;
+
+		val_rrset = val_res->val_rc_rrset;
+		if ((NULL == val_rrset) || (NULL == val_rrset->val_rrset_data)) 
+			continue;
+
+		for(rr = val_rrset->val_rrset_data; rr;
+		    rr = rr->rr_next) {
+
+			if (NULL == rr->rr_rdata)
+				continue;
+
+			/*
+			 * Extract the key from the answer. Ignore any badly
+			 * formatted fingerprints.
+			 */
+			if (!dns_read_rdata(&dnskey_algorithm, &dnskey_digest_type,
+			    &dnskey_digest, &dnskey_digest_len,
+			    rr->rr_rdata,
+			    rr->rr_rdata_length)) {
+				verbose("Error parsing fingerprint from DNS.");
+				continue;
+			}
+
+			++counter;
+
+			/* Check if the current key is the same as the given key */
+			if (hostkey_algorithm == dnskey_algorithm &&
+			    hostkey_digest_type == dnskey_digest_type) {
+
+				if (hostkey_digest_len == dnskey_digest_len &&
+				    memcmp(hostkey_digest, dnskey_digest,
+				    hostkey_digest_len) == 0) {
+
+					debug("found matching fingerprints in DNS");
+					*flags |= DNS_VERIFY_MATCH;
+
+
+
+				}
+			}
+			xfree(dnskey_digest);
+		}
+	    if (val_istrusted(val_res->val_rc_status)) {
+		    /*
+		     * local validation can result in a non-secure, but trusted
+		     * response. For example, in a corporate network the authoritative
+		     * server for internal DNS may be on the internal network, behind
+		     * a firewall. Local validation policy can be configured to trust
+		     * these results without using DNSSEC to validate them.
+		     */
+		    *flags |= DNS_VERIFY_TRUSTED;
+		    if (val_isvalidated(val_res->val_rc_status)) {
+			    *flags |= DNS_VERIFY_SECURE;
+			    debug("found %d trusted fingerprints in DNS", counter);
+		    } else  {
+			    debug("found %d trusted, but not validated, fingerprints in DNS", counter);
+		    }
+	    } else {
+		    debug("found %d un-trusted fingerprints in DNS", counter);
+	    }
+	}
+	if(counter)
+		*flags |= DNS_VERIFY_FOUND;
+
+	xfree(hostkey_digest); /* from key_fingerprint_raw() */
+	val_free_result_chain(val_results);
+#endif /* */
 
 	if (*flags & DNS_VERIFY_FOUND)
 		if (*flags & DNS_VERIFY_MATCH)
diff -I '\$Id: ' -u -r -b -w -p -d --exclude-from=/home/rstory/.rcfiles/diff-ignore --new-file clean/openssh-5.3p1/dns.h openssh-5.3p1/dns.h
--- clean/openssh-5.3p1/dns.h	2006-08-04 22:39:40.000000000 -0400
+++ openssh-5.3p1/dns.h	2009-10-25 14:52:25.000000000 -0400
@@ -45,6 +45,7 @@ enum sshfp_hashes {
 #define DNS_VERIFY_FOUND	0x00000001
 #define DNS_VERIFY_MATCH	0x00000002
 #define DNS_VERIFY_SECURE	0x00000004
+#define DNS_VERIFY_TRUSTED	0x00000008
 
 int	verify_host_key_dns(const char *, struct sockaddr *, const Key *, int *);
 int	export_dns_rr(const char *, const Key *, FILE *, int);
diff -I '\$Id: ' -u -r -b -w -p -d --exclude-from=/home/rstory/.rcfiles/diff-ignore --new-file clean/openssh-5.3p1/readconf.c openssh-5.3p1/readconf.c
--- clean/openssh-5.3p1/readconf.c	2009-07-05 17:12:27.000000000 -0400
+++ openssh-5.3p1/readconf.c	2009-10-25 14:54:32.000000000 -0400
@@ -131,6 +131,7 @@ typedef enum {
 	oSendEnv, oControlPath, oControlMaster, oHashKnownHosts,
 	oTunnel, oTunnelDevice, oLocalCommand, oPermitLocalCommand,
 	oVisualHostKey, oUseRoaming, oZeroKnowledgePasswordAuthentication,
+        oStrictDnssecChecking,oAutoAnswerValidatedKeys,
 	oDeprecated, oUnsupported
 } OpCodes;
 
@@ -235,6 +236,13 @@ static struct {
 #else
 	{ "zeroknowledgepasswordauthentication", oUnsupported },
 #endif
+#ifdef DNSSEC_LOCAL_VALIDATION
+        { "strictdnssecchecking", oStrictDnssecChecking },
+        { "autoanswervalidatedkeys", oAutoAnswerValidatedKeys },
+#else
+        { "strictdnssecchecking", oUnsupported },
+        { "autoanswervalidatedkeys", oUnsupported },
+#endif
 
 	{ NULL, oBadOption }
 };
@@ -490,6 +498,14 @@ parse_yesnoask:
 			*intptr = value;
 		break;
 
+	case oStrictDnssecChecking:
+		intptr = &options->strict_dnssec_checking;
+                goto parse_yesnoask;
+
+	case oAutoAnswerValidatedKeys:
+		intptr = &options->autoanswer_validated_keys;
+                goto parse_yesnoask;
+
 	case oCompression:
 		intptr = &options->compression;
 		goto parse_flag;
@@ -1022,6 +1038,8 @@ initialize_options(Options * options)
 	options->batch_mode = -1;
 	options->check_host_ip = -1;
 	options->strict_host_key_checking = -1;
+	options->strict_dnssec_checking = -1;
+        options->autoanswer_validated_keys = -1;
 	options->compression = -1;
 	options->tcp_keep_alive = -1;
 	options->compression_level = -1;
@@ -1121,6 +1139,10 @@ fill_default_options(Options * options)
 		options->check_host_ip = 1;
 	if (options->strict_host_key_checking == -1)
 		options->strict_host_key_checking = 2;	/* 2 is default */
+	if (options->strict_dnssec_checking == -1)
+		options->strict_dnssec_checking = 2;	/* 2 is default */
+	if (options->autoanswer_validated_keys == -1)
+		options->autoanswer_validated_keys = 0;	/* 0 is default */
 	if (options->compression == -1)
 		options->compression = 0;
 	if (options->tcp_keep_alive == -1)
diff -I '\$Id: ' -u -r -b -w -p -d --exclude-from=/home/rstory/.rcfiles/diff-ignore --new-file clean/openssh-5.3p1/readconf.h openssh-5.3p1/readconf.h
--- clean/openssh-5.3p1/readconf.h	2009-07-05 17:12:27.000000000 -0400
+++ openssh-5.3p1/readconf.h	2009-10-25 14:52:26.000000000 -0400
@@ -125,6 +125,9 @@ typedef struct {
 
 	int	use_roaming;
 
+	int     strict_dnssec_checking;	/* Strict DNSSEC checking. */
+	int     autoanswer_validated_keys;
+
 }       Options;
 
 #define SSHCTL_MASTER_NO	0
diff -I '\$Id: ' -u -r -b -w -p -d --exclude-from=/home/rstory/.rcfiles/diff-ignore --new-file clean/openssh-5.3p1/sshconnect.c openssh-5.3p1/sshconnect.c
--- clean/openssh-5.3p1/sshconnect.c	2009-06-21 04:53:53.000000000 -0400
+++ openssh-5.3p1/sshconnect.c	2009-10-25 14:52:26.000000000 -0400
@@ -26,6 +26,10 @@
 #include <netinet/in.h>
 #include <arpa/inet.h>
 
+#ifdef DNSSEC_LOCAL_VALIDATION
+# include <validator/validator.h>
+#endif
+
 #include <ctype.h>
 #include <errno.h>
 #include <netdb.h>
@@ -63,6 +67,9 @@ char *client_version_string = NULL;
 char *server_version_string = NULL;
 
 static int matching_host_key_dns = 0;
+#ifdef DNSSEC_LOCAL_VALIDATION
+static int validated_host_key_dns = 0;
+#endif
 
 /* import */
 extern Options options;
@@ -73,6 +80,7 @@ extern pid_t proxy_command_pid;
 
 static int show_other_keys(const char *, Key *);
 static void warn_changed_key(Key *);
+static int confirm(const char *prompt);
 
 /*
  * Connect to the given ssh server using a proxy command.
@@ -323,7 +331,11 @@ ssh_connect(const char *host, struct soc
 	int on = 1;
 	int sock = -1, attempt;
 	char ntop[NI_MAXHOST], strport[NI_MAXSERV];
-	struct addrinfo hints, *ai, *aitop;
+	struct addrinfo hints;
+	struct addrinfo *ai, *aitop = NULL;
+#ifdef DNSSEC_LOCAL_VALIDATION
+	val_status_t val_status;
+#endif
 
 	debug2("ssh_connect: needpriv %d", needpriv);
 
@@ -337,9 +349,47 @@ ssh_connect(const char *host, struct soc
 	hints.ai_family = family;
 	hints.ai_socktype = SOCK_STREAM;
 	snprintf(strport, sizeof strport, "%u", port);
+#ifndef DNSSEC_LOCAL_VALIDATION
 	if ((gaierr = getaddrinfo(host, strport, &hints, &aitop)) != 0)
 		fatal("%s: Could not resolve hostname %.100s: %s", __progname,
 		    host, ssh_gai_strerror(gaierr));
+#else
+	if ((gaierr = val_getaddrinfo(NULL, host, strport, &hints, &aitop,
+							 &val_status)) != 0) 
+		fatal("%s: Could not resolve hostname %.100s: %s", __progname,
+		    host, ssh_gai_strerror(gaierr));
+ 	debug("ValStatus: %s", p_val_status(val_status));
+ 	if (!val_istrusted(val_status)) {
+            error("@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@");
+            error("@ WARNING: UNTRUSTED DNS RESOLUTION FOR HOST IP ADRRESS! @");
+            error("@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@");
+            error("The authenticity of DNS data for the host '%.200s' "
+                  "can't be established.", host);
+            if (options.strict_dnssec_checking == 1) {
+                fatal("DNS resolution is not trusted (%s) "
+                      "and you have requested strict checking",
+                      p_val_status(val_status));
+            } else if (options.strict_dnssec_checking == 2) {
+                char msg[1024];
+                for (ai = aitop; ai; ai = ai->ai_next) {
+                    if (ai->ai_family != AF_INET && ai->ai_family != AF_INET6)
+                        continue;
+                    if (getnameinfo(ai->ai_addr, ai->ai_addrlen,
+                            ntop, sizeof(ntop), strport, sizeof(strport),
+                            NI_NUMERICHOST|NI_NUMERICSERV) != 0) {
+                        error("ssh_connect: getnameinfo failed");
+                        continue;
+                    }
+                    error(" IP address %s port %s", ntop, strport);
+                }
+                snprintf(msg,sizeof(msg),
+                         "Are you sure you want to attempt to connect "
+                         "(yes/no)? ");
+                if (!confirm(msg)) 
+                    return (-1);
+            }
+ 	}
+#endif /* DNSSEC_LOCAL_VALIDATION */
 
 	for (attempt = 0; attempt < connection_attempts; attempt++) {
 		if (attempt > 0) {
@@ -736,6 +786,7 @@ check_host_key(char *hostname, struct so
 		}
 		break;
 	case HOST_NEW:
+		debug("Host '%.200s' new.", host);
 		if (options.host_key_alias == NULL && port != 0 &&
 		    port != SSH_DEFAULT_PORT) {
 			debug("checking without port identifier");
@@ -781,6 +832,17 @@ check_host_key(char *hostname, struct so
 					    "No matching host key fingerprint"
 					    " found in DNS.\n");
 			}
+#ifdef DNSSEC_LOCAL_VALIDATION
+                        if (options.autoanswer_validated_keys &&
+                            validated_host_key_dns && matching_host_key_dns) {
+                            snprintf(msg, sizeof(msg),
+                                     "The authenticity of host '%.200s (%s)' was "
+                                     " validated via DNSSEC%s",
+                                     host, ip, msg1);
+                            logit(msg);
+                            xfree(fp);
+                        } else {
+#endif
 			snprintf(msg, sizeof(msg),
 			    "The authenticity of host '%.200s (%s)' can't be "
 			    "established%s\n"
@@ -795,6 +857,9 @@ check_host_key(char *hostname, struct so
 			xfree(fp);
 			if (!confirm(msg))
 				goto fail;
+#ifdef DNSSEC_LOCAL_VALIDATION
+                        }
+#endif
 		}
 		/*
 		 * If not in strict mode, add the key automatically to the
@@ -830,6 +895,7 @@ check_host_key(char *hostname, struct so
 			    "list of known hosts.", hostp, type);
 		break;
 	case HOST_CHANGED:
+		debug("Host '%.200s' changed.", host);
 		if (readonly == ROQUIET)
 			goto fail;
 		if (options.check_host_ip && host_ip_differ) {
@@ -840,6 +906,8 @@ check_host_key(char *hostname, struct so
 				key_msg = "is unchanged";
 			else
 				key_msg = "has a different value";
+#ifdef DNSSEC_LOCAL_VALIDATION
+                        if (!validated_host_key_dns) {
 			error("@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@");
 			error("@       WARNING: POSSIBLE DNS SPOOFING DETECTED!          @");
 			error("@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@");
@@ -848,6 +916,19 @@ check_host_key(char *hostname, struct so
 			error("%s. This could either mean that", key_msg);
 			error("DNS SPOOFING is happening or the IP address for the host");
 			error("and its host key have changed at the same time.");
+                        }
+                        else {
+#endif
+			error("@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@");
+			error("@       WARNING: HOST IP ADDRESS HAS CHANGED!             @");
+			error("@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@");
+                        error("The %s host key for %s has changed,", type, host);
+			error("and the key for the according IP address %s", ip);
+			error("%s. The IP address for the host", key_msg);
+			error("and its host key have changed at the same time.");
+#ifdef DNSSEC_LOCAL_VALIDATION
+                        }
+#endif
 			if (ip_status != HOST_NEW)
 				error("Offending key for IP in %s:%d", ip_file, ip_line);
 		}
@@ -861,12 +942,54 @@ check_host_key(char *hostname, struct so
 		 * If strict host key checking is in use, the user will have
 		 * to edit the key manually and we can only abort.
 		 */
+#ifdef DNSSEC_LOCAL_VALIDATION
+		if ((options.strict_host_key_checking == 2) &&
+                    options.autoanswer_validated_keys &&
+                    matching_host_key_dns && validated_host_key_dns) {
+                    logit("The authenticity of host '%.200s (%s)' was "
+                          " validated via DNSSEC.",
+                          host, ip);
+                    /*
+                     * If not in strict mode, add the key automatically to the
+                     * local known_hosts file.
+                     */
+                    if (options.check_host_ip && ip_status == HOST_NEW) {
+			snprintf(hostline, sizeof(hostline), "%s,%s",
+                                 host, ip);
+			hostp = hostline;
+			if (options.hash_known_hosts) {
+                            /* Add hash of host and IP separately */
+                            r = add_host_to_hostfile(user_hostfile, host,
+                                                     host_key, options.hash_known_hosts) &&
+                                add_host_to_hostfile(user_hostfile, ip,
+                                                     host_key, options.hash_known_hosts);
+			} else {
+                            /* Add unhashed "host,ip" */
+                            r = add_host_to_hostfile(user_hostfile,
+                                                     hostline, host_key,
+                                                     options.hash_known_hosts);
+			}
+                    } else {
+			r = add_host_to_hostfile(user_hostfile, host, host_key,
+                                                 options.hash_known_hosts);
+			hostp = host;
+                    }
+                    
+                    if (!r)
+			logit("Failed to add the host to the list of known "
+                              "hosts (%.500s).", user_hostfile);
+                    else
+			logit("Warning: Permanently added '%.200s' (%s) to the "
+                              "list of known hosts.", hostp, type);
+                }
+                else
+#endif
 		if (options.strict_host_key_checking) {
 			error("%s host key for %.200s has changed and you have "
 			    "requested strict checking.", type, host);
 			goto fail;
 		}
-
+                else {
 		/*
 		 * If strict host key checking has not been requested, allow
 		 * the connection but without MITM-able authentication or
@@ -925,9 +1048,10 @@ check_host_key(char *hostname, struct so
 		 * XXX Should permit the user to change to use the new id.
 		 * This could be done by converting the host key to an
 		 * identifying sentence, tell that the host identifies itself
-		 * by that sentence, and ask the user if he/she whishes to
+		 * by that sentence, and ask the user if he/she wishes to
 		 * accept the authentication.
 		 */
+                }
 		break;
 	case HOST_FOUND:
 		fatal("internal error");
@@ -952,10 +1076,19 @@ check_host_key(char *hostname, struct so
 			error("Exiting, you have requested strict checking.");
 			goto fail;
 		} else if (options.strict_host_key_checking == 2) {
+#ifdef DNSSEC_LOCAL_VALIDATION
+                    if (options.autoanswer_validated_keys &&
+                        matching_host_key_dns && validated_host_key_dns) {
+			logit("%s", msg);
+                    } else {
+#endif
 			strlcat(msg, "\nAre you sure you want "
 			    "to continue connecting (yes/no)? ", sizeof(msg));
 			if (!confirm(msg))
 				goto fail;
+#ifdef DNSSEC_LOCAL_VALIDATION
+                    }
+#endif
 		} else {
 			logit("%s", msg);
 		}
@@ -981,12 +1114,42 @@ verify_host_key(char *host, struct socka
 	if (options.verify_host_key_dns &&
 	    verify_host_key_dns(host, hostaddr, host_key, &flags) == 0) {
 
+#ifdef DNSSEC_LOCAL_VALIDATION
+		/*
+		 * local validation can result in a non-secure, but trusted
+		 * response. For example, in a corporate network the authoritative
+		 * server for internal DNS may be on the internal network, behind
+		 * a firewall. Local validation policy can be configured to trust
+		 * these results without using DNSSEC to validate them.
+		 */
+		if (!(flags & DNS_VERIFY_TRUSTED)) {
+			error("@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@");
+			error("@  WARNING: UNTRUSTED DNS RESOLUTION FOR HOST KEY!       @");
+			error("@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@");
+		}
+                if (flags & DNS_VERIFY_SECURE)
+                    validated_host_key_dns = 1;
+#endif
 		if (flags & DNS_VERIFY_FOUND) {
 
 			if (options.verify_host_key_dns == 1 &&
 			    flags & DNS_VERIFY_MATCH &&
 			    flags & DNS_VERIFY_SECURE)
+#ifndef DNSSEC_LOCAL_VALIDATION
 				return 0;
+#else
+                        {
+                            if (flags & DNS_VERIFY_MATCH)
+				matching_host_key_dns = 1;
+                            if (options.autoanswer_validated_keys)
+                                return check_host_key(host, hostaddr, options.port,
+                                                      host_key, RDRW,
+                                                      options.user_hostfile,
+                                                      options.system_hostfile);
+                            else
+				return 0;
+                        }
+#endif
 
 			if (flags & DNS_VERIFY_MATCH) {
 				matching_host_key_dns = 1;
@@ -1137,9 +1300,18 @@ warn_changed_key(Key *host_key)
 	error("@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@");
 	error("@    WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED!     @");
 	error("@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@");
+#ifdef DNSSEC_LOCAL_VALIDATION
+        if (matching_host_key_dns && validated_host_key_dns) {
+            error("Howerver, a matching host key, validated by DNSSEC, was found.");
+        }
+        else {
+#endif
 	error("IT IS POSSIBLE THAT SOMEONE IS DOING SOMETHING NASTY!");
 	error("Someone could be eavesdropping on you right now (man-in-the-middle attack)!");
 	error("It is also possible that the %s host key has just been changed.", type);
+#ifdef DNSSEC_LOCAL_VALIDATION
+        }
+#endif
 	error("The fingerprint for the %s key sent by the remote host is\n%s.",
 	    type, fp);
 	error("Please contact your system administrator.");
