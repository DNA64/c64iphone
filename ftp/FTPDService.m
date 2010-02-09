//
//  FTPDService.m
//  Test
//
//  Created by Stuart Carnie on 1/28/10.
//  Copyright 2010 __MyCompanyName__. All rights reserved.
//

#import "FTPDService.h"


@implementation FTPDService

@synthesize ftpService;
@synthesize ftpOn;

typedef struct PureFTPd_SiteCallback_ {
    int return_code;
    char *response;
} PureFTPd_SiteCallback;

extern void pureftpd_register_login_callback(void (*callback)(void *user_data), void *user_data);
extern void pureftpd_register_logout_callback(void (*callback)(void *user_data), void *user_data);
extern void pureftpd_register_log_callback(void (*callback)(int crit, const char *message, void *user_data), void *user_data);
extern void pureftpd_register_simple_auth_callback(int (*callback)(const char *account, const char *password, void *user_data), void *user_data);
extern int  pureftpd_start(int argc, char *argv[], const char *baseDir);
extern int  pureftpd_shutdown(void);
extern int  pureftpd_enable(void);
extern int  pureftpd_disable(void);

void pureftpd_register_site_callback(const char *site_command, PureFTPd_SiteCallback *(*callback)(const char *arg, void *user_data), void (*free_callback)(PureFTPd_SiteCallback *site_callback, void *user_data), void *user_data);

// 0: The switch totally shuts the server down
// 1: The switch accepts / refuses new connections without shutting the server down
#define kSUSPEND_INSTEAD_OF_SHUTDOWN 0

// 0: Require authentication (see the authentication callback below)
// 1: Allow anonymous connections (ftp/anonymous)
#define kALLOW_ANONYMOUS_CONNECTIONS 1

static NSString *baseDir;

- (void) getBaseDir {
	baseDir = nil;
	NSFileManager *fileManager = [NSFileManager defaultManager];
	NSArray *dirs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
	NSDictionary *attrs;
	for (NSString *dir in dirs) {
		attrs = [fileManager attributesOfItemAtPath: dir error: NULL];
		if (attrs == nil) {
			NSLog(@"[%@] is not an option", dir);
			continue;
		}
		NSString *fileType = [attrs fileType];
		if (![fileType isEqualToString: @"NSFileTypeDirectory"]) {
			NSLog(@"[%@] is not a directory", dir);
			continue;			
		}
		if ([fileManager isWritableFileAtPath: dir] != TRUE) {
			NSLog(@"[%@] isn't a writeable directory", dir);
			continue;						
		}
		baseDir = dir;
		break;
	}
	[baseDir retain];
}

PureFTPd_SiteCallback *ftpSiteCallPingCallback(const char *arg, void *user_data) {
	NSLog(@"SITE PING command called with argument [%s]", arg);
	PureFTPd_SiteCallback *site_callback = malloc(sizeof *site_callback);
	site_callback->return_code = 200;
	char *response;
	asprintf(&response, "PONG! [%s]", arg);
	site_callback->response = response;
	
	return site_callback;
}

void ftpSiteCallFreePingCallback(PureFTPd_SiteCallback *site_callback, void *user_data) {
	NSLog(@"SITE PING command done - releasing allocated data");
	free(site_callback->response);
	free(site_callback);
}

void ftpLoginCallback(void *userData) {
	NSLog(@"A client just logged in");
}

void ftpLogoutCallback(void *userData) {
	NSLog(@"A client just logged out");
}

void ftpLogCallback(int crit, const char *message, void *userData) {
	NSLog(@"LOG(%d) [%s]", crit, message);
}

int  ftpAuthCallback(const char *account, const char *password, void *userData) {
	if (strcmp(account, "root") == 0 && strcmp(password, "alpine") == 0) {
		return 1;
	}
	return -1;
}

- (void) ftpthread: (id) fodder {
	[[NSAutoreleasePool alloc] init];
	char *args[] = {
#if kALLOW_ANONYMOUS_CONNECTIONS
		"pure-ftpd", "--anonymouscancreatedirs", "--dontresolve", "--allowdotfiles", "--customerproof",
#else
		"pure-ftpd", "--dontresolve", "--allowdotfiles", "--customerproof", "--noanonymous",		
#endif		
		NULL
	};
	pureftpd_register_login_callback(ftpLoginCallback, self);
	pureftpd_register_logout_callback(ftpLogoutCallback, self);
	pureftpd_register_log_callback(ftpLogCallback, self);
	pureftpd_register_simple_auth_callback(ftpAuthCallback, self);
	pureftpd_register_site_callback("PING", ftpSiteCallPingCallback, ftpSiteCallFreePingCallback, NULL);
	NSLog(@"Server started");
	for (;;) {		
		pureftpd_start((int) (sizeof args / sizeof *args) - 1, args, [baseDir UTF8String]);
		if (ftpOn == FALSE) {
			break;
		}
		NSLog(@"Server immediately restarted");		
	}
	NSLog(@"Server stopped");
}

- (void) ftpStart {
	NSLog(@"Turning FTP server ON...");
	ftpOn = TRUE;
	//[viewController showFtpActivity: TRUE];	
	[ftpService publish];
	[NSThread detachNewThreadSelector: @selector(ftpthread:) toTarget:self withObject:nil];
}

- (void) ftpStop {
	NSLog(@"Turning FTP server OFF");	
	ftpOn = FALSE;
	//[viewController showFtpActivity: FALSE];
	[ftpService stop];
	pureftpd_shutdown();	
}

- (void) ftpEnable {
	NSLog(@"Accepting client connections");
	//[viewController showFtpActivity: TRUE];
	[ftpService publish];
	pureftpd_enable();
}

- (void) ftpDisable {
	NSLog(@"Refusing client connections");
	//[viewController showFtpActivity: FALSE];
	[ftpService stop];
	pureftpd_disable();
}

- (void) ftpOnOffStatusChanged: (NSNotification *) notification {
	const BOOL on = [(NSNumber *) [notification.userInfo objectForKey: @"on"] boolValue];
#if kSUSPEND_INSTEAD_OF_SHUTDOWN
	if (on) {
		[self ftpEnable];
	} else {
		[self ftpDisable];
	}	
#else
	if (on) {
		[self ftpStart];
	} else {
		[self ftpStop];
	}
#endif
}

- (void)start {   
	[self getBaseDir];
	ftpService = [[NSNetService alloc] initWithDomain:@"" type:@"_ftp._tcp" name:@"iPhone FTP Server" port: 2121];
	[[NSNotificationCenter defaultCenter] addObserver: self selector: @selector(ftpOnOffStatusChanged:) name: @"ftp_on_off_status_changed" object: nil];
		
	[self ftpStart];
}

- (void) dealloc {
	[ftpService stop];
	[ftpService release];
    [super dealloc];
}
@end
