//
//  TICDSApplicationSyncManager.m
//  ShoppingListMac
//
//  Created by Tim Isted on 21/04/2011.
//  Copyright 2011 Tim Isted. All rights reserved.
//

#import "TICoreDataSync.h"

@interface TICDSApplicationSyncManager ()

- (BOOL)startRegistrationProcess:(NSError **)outError;
- (void)bailFromRegistrationProcessWithError:(NSError *)anError;
- (BOOL)getAvailablePreviouslySynchronizedDocuments:(NSError **)outError;
- (void)bailFromDocumentDownloadProcessForDocumentWithIdentifier:(NSString *)anIdentifier error:(NSError *)anError;
- (BOOL)startDocumentDownloadProcessForDocumentWithIdentifier:(NSString *)anIdentifier toLocation:(NSURL *)aLocation error:(NSError **)outError;

@property (nonatomic, assign) TICDSApplicationSyncManagerState state;
@property (nonatomic, retain) NSString *appIdentifier;
@property (nonatomic, retain) NSString *clientIdentifier;
@property (nonatomic, retain) NSString *clientDescription;
@property (nonatomic, retain) NSDictionary *applicationUserInfo;

@end

@implementation TICDSApplicationSyncManager

#pragma mark -
#pragma mark REGISTRATION
- (void)registerWithDelegate:(id <TICDSApplicationSyncManagerDelegate>)aDelegate globalAppIdentifier:(NSString *)anAppIdentifier uniqueClientIdentifier:(NSString *)aClientIdentifier description:(NSString *)aClientDescription userInfo:(NSDictionary *)someUserInfo
{
    [self setState:TICDSApplicationSyncManagerStateRegistering];
    TICDSLog(TICDSLogVerbosityStartAndEndOfMainPhase, @"Starting to register application sync manager");
    
    TICDSLog(TICDSLogVerbosityEveryStep, @"Registration Information:\n   Delegate: %@,\n   Global App ID: %@,\n   Client ID: %@,\n   Description: %@\nUser Info: %@", aDelegate, anAppIdentifier, aClientIdentifier, aClientDescription, someUserInfo);
    
    [self setDelegate:aDelegate];
    [self setAppIdentifier:anAppIdentifier];
    [self setClientIdentifier:aClientIdentifier];
    [self setClientDescription:aClientDescription];
    [self setApplicationUserInfo:someUserInfo];
    
    NSError *anyError = nil;
    BOOL shouldContinue = [self startRegistrationProcess:&anyError];
    if( !shouldContinue ) {
        TICDSLog(TICDSLogVerbosityErrorsOnly, @"Error registering: %@", anyError);
        [self bailFromRegistrationProcessWithError:anyError];
        return;
    }
    
    [self ti_alertDelegateWithSelector:@selector(applicationSyncManagerDidBeginRegistering:)];
}

- (void)bailFromRegistrationProcessWithError:(NSError *)anError
{
    TICDSLog(TICDSLogVerbosityErrorsOnly, @"Bailing from application registration process");
    [self ti_alertDelegateWithSelector:@selector(applicationSyncManger:didFailToRegisterWithError:), anError];
}

- (BOOL)startRegistrationProcess:(NSError **)outError
{
    TICDSApplicationRegistrationOperation *operation = [self applicationRegistrationOperation];
    
    if( !operation ) {
        if( outError ) {
            *outError = [TICDSError errorWithCode:TICDSErrorCodeFailedToCreateOperationObject classAndMethod:__PRETTY_FUNCTION__];
        }
        
        return NO;
    }
    
    [operation setAppIdentifier:[self appIdentifier]];
    [operation setClientDescription:[self clientDescription]];
    [operation setClientIdentifier:[self clientIdentifier]];
    [operation setApplicationUserInfo:[self applicationUserInfo]];
    
    [[self registrationQueue] addOperation:operation];
    
    return YES;
}

#pragma mark Operation Generation
- (TICDSApplicationRegistrationOperation *)applicationRegistrationOperation
{
    return [[[TICDSApplicationRegistrationOperation alloc] initWithDelegate:self] autorelease];
}

#pragma mark Operation Communications
- (void)applicationRegistrationOperationCompleted:(TICDSApplicationRegistrationOperation *)anOperation
{
    TICDSLog(TICDSLogVerbosityStartAndEndOfEachPhase, @"Application Registration Operation Completed");
    
    [self setState:TICDSApplicationSyncManagerStateAbleToSync];
    TICDSLog(TICDSLogVerbosityStartAndEndOfMainPhase, @"Finished registering application sync manager");
    
    // Registration Complete
    [self ti_alertDelegateWithSelector:@selector(applicationSyncManagerDidFinishRegistering:)];
    
    TICDSLog(TICDSLogVerbosityEveryStep, @"Resuming Operation Queues");
    [[self otherTasksQueue] setSuspended:NO];
    
    [[NSNotificationCenter defaultCenter] postNotificationName:TICDSApplicationSyncManagerDidFinishRegisteringNotification object:self];
}

- (void)applicationRegistrationOperationWasCancelled:(TICDSApplicationRegistrationOperation *)anOperation
{
    [self setState:TICDSApplicationSyncManagerStateNotYetRegistered];
    TICDSLog(TICDSLogVerbosityErrorsOnly, @"Application Registration Operation was Cancelled");
    
    [self ti_alertDelegateWithSelector:@selector(applicationSyncManger:didFailToRegisterWithError:), [TICDSError errorWithCode:TICDSErrorCodeTaskWasCancelled classAndMethod:__PRETTY_FUNCTION__]];
}

- (void)applicationRegistrationOperation:(TICDSApplicationRegistrationOperation *)anOperation failedToCompleteWithError:(NSError *)anError
{
    [self setState:TICDSApplicationSyncManagerStateNotYetRegistered];
    TICDSLog(TICDSLogVerbosityErrorsOnly, @"Application Registration Operation Failed to Complete with Error: %@", anError);
    [self ti_alertDelegateWithSelector:@selector(applicationSyncManger:didFailToRegisterWithError:), anError];
}

#pragma mark -
#pragma mark LIST OF PREVIOUSLY SYNCHRONIZED DOCUMENTS
- (void)requestListOfPreviouslySynchronizedDocuments
{
    TICDSLog(TICDSLogVerbosityStartAndEndOfMainPhase, @"Starting to check for remote documents that have been previously synchronized");
    [self ti_alertDelegateWithSelector:@selector(applicationSyncManagerDidBeginCheckingForPreviouslySynchronizedDocuments:)];
    
    NSError *anyError = nil;
    BOOL success = [self getAvailablePreviouslySynchronizedDocuments:&anyError];
    
    if( !success ) {
        TICDSLog(TICDSLogVerbosityErrorsOnly, @"Request for list of previously-synchronized documents failed with error: %@", anyError);
        [self ti_alertDelegateWithSelector:@selector(applicationSyncManager:didFailToCheckForPreviouslySynchronizedDocumentsWithError:), anyError];
    }
}

- (BOOL)getAvailablePreviouslySynchronizedDocuments:(NSError **)outError
{
    TICDSListOfPreviouslySynchronizedDocumentsOperation *operation = [self listOfPreviouslySynchronizedDocumentsOperation];
    
    if( !operation ) {
        if( outError ) {
            *outError = [TICDSError errorWithCode:TICDSErrorCodeFailedToCreateOperationObject classAndMethod:__PRETTY_FUNCTION__];
        }
        
        return NO;
    }
    
    [[self otherTasksQueue] addOperation:operation];
    
    return YES;
}

- (void)gotNoPreviouslySynchronizedDocuments
{
    TICDSLog(TICDSLogVerbosityEveryStep, @"Didn't get any available documents");
    [self ti_alertDelegateWithSelector:@selector(applicationSyncManagerDidFinishCheckingAndFoundNoPreviouslySynchronizedDocuments:)];
}

- (void)gotAvailablePreviouslySynchronizedDocuments:(NSArray *)anArray
{
    if( [anArray count] < 1 ) {
        [self gotNoPreviouslySynchronizedDocuments];
        return;
    }
    
    TICDSLog(TICDSLogVerbosityStartAndEndOfMainPhase, @"Found previously-synchronized remote documents: %@", anArray);
    [self ti_alertDelegateWithSelector:@selector(applicationSyncManager:didFinishCheckingAndFoundPreviouslySynchronizedDocuments:), anArray];
}

#pragma mark Operation Generation
- (TICDSListOfPreviouslySynchronizedDocumentsOperation *)listOfPreviouslySynchronizedDocumentsOperation
{
    return [[[TICDSListOfPreviouslySynchronizedDocumentsOperation alloc] initWithDelegate:self] autorelease];
}

#pragma mark Operation Communications
- (void)listOfDocumentsOperationCompleted:(TICDSListOfPreviouslySynchronizedDocumentsOperation *)anOperation
{
    TICDSLog(TICDSLogVerbosityStartAndEndOfEachPhase, @"List of Previously-Synchronized Documents Operation Completed");
    [self gotAvailablePreviouslySynchronizedDocuments:[anOperation availableDocuments]];
}

- (void)listOfDocumentsOperationWasCancelled:(TICDSListOfPreviouslySynchronizedDocumentsOperation *)anOperation
{
    TICDSLog(TICDSLogVerbosityErrorsOnly, @"List of Previously-Synchronized Documents Operation was Cancelled");
    [self gotNoPreviouslySynchronizedDocuments];
}

- (void)listOfDocumentsOperation:(TICDSListOfPreviouslySynchronizedDocumentsOperation *)anOperation failedToCompleteWithError:(NSError *)anError
{
    TICDSLog(TICDSLogVerbosityErrorsOnly, @"List of Previously-Synchronized Documents Operation Failed to Complete with Error: %@", anError);
    [self ti_alertDelegateWithSelector:@selector(applicationSyncManager:didFailToCheckForPreviouslySynchronizedDocumentsWithError:), anError];
}

#pragma mark -
#pragma mark DOCUMENT DOWNLOAD
- (void)requestDownloadOfDocumentWithIdentifier:(NSString *)anIdentifier toLocation:(NSURL *)aLocation
{
    TICDSLog(TICDSLogVerbosityStartAndEndOfMainPhase, @"Starting to download a previously synchronized document %@ to %@", anIdentifier, aLocation);
    
    [self ti_alertDelegateWithSelector:@selector(applicationSyncManager:didBeginDownloadingDocumentWithIdentifier:), anIdentifier];
    
    NSError *anyError = nil;
    BOOL success = [self startDocumentDownloadProcessForDocumentWithIdentifier:anIdentifier toLocation:aLocation error:&anyError];
    
    if( !success ) {
        TICDSLog(TICDSLogVerbosityErrorsOnly, @"Download of previously-synchronized document failed with error: %@", anyError);
        [self bailFromDocumentDownloadProcessForDocumentWithIdentifier:anIdentifier error:anyError];
    }
}

- (void)bailFromDocumentDownloadProcessForDocumentWithIdentifier:(NSString *)anIdentifier error:(NSError *)anError
{
    TICDSLog(TICDSLogVerbosityErrorsOnly, @"Bailing from document download process");
    [self ti_alertDelegateWithSelector:@selector(applicationSyncManager:didFailToDownloadDocumentWithIdentifier:error:), anIdentifier, anError];
}

- (BOOL)startDocumentDownloadProcessForDocumentWithIdentifier:(NSString *)anIdentifier toLocation:(NSURL *)aLocation error:(NSError **)outError
{
    // Set download to go to a temporary location
    NSString *temporaryPath = [NSTemporaryDirectory() stringByAppendingPathComponent:TICDSFrameworkName];
    temporaryPath = [temporaryPath stringByAppendingPathComponent:anIdentifier];
    
    NSError *anyError = nil;
    BOOL success = [[self fileManager] createDirectoryAtPath:temporaryPath withIntermediateDirectories:YES attributes:nil error:&anyError];
    
    if( !success ) {
        TICDSLog(TICDSLogVerbosityErrorsOnly, @"Failed to create temporary directory for document download: %@", anyError);
        
        if( outError ) {
            *outError = [TICDSError errorWithCode:TICDSErrorCodeFileManagerError underlyingError:anyError classAndMethod:__PRETTY_FUNCTION__];
        }
        
        return NO;
    }
    
    TICDSWholeStoreDownloadOperation *operation = [self wholeStoreDownloadOperationForDocumentWithIdentifier:(NSString *)anIdentifier];
    
    if( !operation ) {
        if( outError ) {
            *outError = [TICDSError errorWithCode:TICDSErrorCodeFailedToCreateOperationObject classAndMethod:__PRETTY_FUNCTION__];
        }
        
        return NO;
    }
    
    [operation setUserInfo:[NSDictionary dictionaryWithObjectsAndKeys:aLocation, kTICDSDocumentDownloadFinalWholeStoreLocation, anIdentifier, kTICDSDocumentIdentifier, nil]];
    
    NSString *wholeStoreFilePath = [temporaryPath stringByAppendingPathComponent:TICDSWholeStoreFilename];
    NSString *appliedSyncChangesFilePath = [temporaryPath stringByAppendingPathComponent:TICDSAppliedSyncChangeSetsFilename];
    
    [operation setLocalWholeStoreFileLocation:[NSURL fileURLWithPath:wholeStoreFilePath]];
    [operation setLocalAppliedSyncChangeSetsFileLocation:[NSURL fileURLWithPath:appliedSyncChangesFilePath]];
    
    [operation setClientIdentifier:[self clientIdentifier]];
    
    [[self otherTasksQueue] addOperation:operation];
    
    return YES;
}

#pragma mark Overridden Methods
- (TICDSWholeStoreDownloadOperation *)wholeStoreDownloadOperationForDocumentWithIdentifier:(NSString *)anIdentifier
{
    return [[[TICDSWholeStoreDownloadOperation alloc] initWithDelegate:self] autorelease];
}

#pragma mark -
#pragma mark Post-Operation Work
- (void)bailFromDocumentDownloadPostProcessingForOperation:(TICDSWholeStoreDownloadOperation *)anOperation withError:(NSError *)anError
{
    [self ti_alertDelegateWithSelector:@selector(applicationSyncManager:didFailToDownloadDocumentWithIdentifier:error:), [[anOperation userInfo] valueForKey:kTICDSDocumentIdentifier], anError];
}

#pragma mark Operation Communications
- (void)documentDownloadOperationCompleted:(TICDSWholeStoreDownloadOperation *)anOperation
{
    NSError *anyError = nil;
    BOOL success = YES;
    
    NSURL *finalWholeStoreLocation = [[anOperation userInfo] valueForKey:kTICDSDocumentDownloadFinalWholeStoreLocation];
    
    // Remove existing WholeStore, if necessary
    if( [[self fileManager] fileExistsAtPath:[finalWholeStoreLocation path]] ) {
        [self ti_alertDelegateWithSelector:@selector(applicationSyncManager:willReplaceWholeStoreFileForDocumentWithIdentifier:atURL:), [[anOperation userInfo] valueForKey:kTICDSDocumentIdentifier], finalWholeStoreLocation];
        
        success = [[self fileManager] removeItemAtPath:[finalWholeStoreLocation path] error:&anyError];
        
        if( !success ) {
            [self bailFromDocumentDownloadPostProcessingForOperation:anOperation withError:[TICDSError errorWithCode:TICDSErrorCodeFileManagerError underlyingError:anyError classAndMethod:__PRETTY_FUNCTION__]];
            return;
        }
    }
    
    // Move downloaded WholeStore
    success = [[self fileManager] moveItemAtPath:[[anOperation localWholeStoreFileLocation] path] toPath:[finalWholeStoreLocation path] error:&anyError];
    if( !success ) {
        [self bailFromDocumentDownloadPostProcessingForOperation:anOperation withError:[TICDSError errorWithCode:TICDSErrorCodeFileManagerError underlyingError:anyError classAndMethod:__PRETTY_FUNCTION__]];
        return;
    }
    
    // Get document sync manager from delegate
    TICDSDocumentSyncManager *documentSyncManager = [self ti_objectFromDelegateWithSelector:@selector(applicationSyncManager:preConfiguredDocumentSyncManagerForDownloadedDocumentWithIdentifier:atURL:), [[anOperation userInfo] valueForKey:kTICDSDocumentIdentifier], finalWholeStoreLocation];
    
    if( !documentSyncManager ) {
        // TODO: ALERT DELEGATE AND BAIL
    }
    
    NSString *finalAppliedSyncChangeSetsPath = [documentSyncManager localAppliedSyncChangesFilePath];
    
    // Remove existing applied sync changes, if necessary
    if( [[self fileManager] fileExistsAtPath:finalAppliedSyncChangeSetsPath] && ![[self fileManager] removeItemAtPath:finalAppliedSyncChangeSetsPath error:&anyError] ) {
        [self bailFromDocumentDownloadPostProcessingForOperation:anOperation withError:[TICDSError errorWithCode:TICDSErrorCodeFileManagerError underlyingError:anyError classAndMethod:__PRETTY_FUNCTION__]];
        return;
    }
    
    // Move new applied sync changes, if necessary
    if( [[self fileManager] fileExistsAtPath:[[anOperation localAppliedSyncChangeSetsFileLocation] path]] && ![[self fileManager] moveItemAtPath:[[anOperation localAppliedSyncChangeSetsFileLocation] path] toPath:finalAppliedSyncChangeSetsPath error:&anyError] ) {
        [self bailFromDocumentDownloadPostProcessingForOperation:anOperation withError:[TICDSError errorWithCode:TICDSErrorCodeFileManagerError underlyingError:anyError classAndMethod:__PRETTY_FUNCTION__]];
        return;
    }
    
    TICDSLog(TICDSLogVerbosityStartAndEndOfEachPhase, @"Document Download Operation Completed");
    [self ti_alertDelegateWithSelector:@selector(applicationSyncManager:didFinishDownloadingDocumentWithIdentifier:atURL:), [[anOperation userInfo] valueForKey:kTICDSDocumentIdentifier], finalWholeStoreLocation];
}

- (void)documentDownloadOperationWasCancelled:(TICDSWholeStoreDownloadOperation *)anOperation
{
    TICDSLog(TICDSLogVerbosityErrorsOnly, @"Document Download Operation was Cancelled");
    [self ti_alertDelegateWithSelector:@selector(applicationSyncManager:didFailToDownloadDocumentWithIdentifier:error:), [[anOperation userInfo] valueForKey:kTICDSDocumentIdentifier], [TICDSError errorWithCode:TICDSErrorCodeTaskWasCancelled classAndMethod:__PRETTY_FUNCTION__]];
}

- (void)documentDownloadOperation:(TICDSWholeStoreDownloadOperation *)anOperation failedToCompleteWithError:(NSError *)anError
{
    TICDSLog(TICDSLogVerbosityErrorsOnly, @"Document Download Operation Failed to Complete with Error: %@", anError);
    [self ti_alertDelegateWithSelector:@selector(applicationSyncManager:didFailToDownloadDocumentWithIdentifier:error:), [[anOperation userInfo] valueForKey:kTICDSDocumentIdentifier], anError];
}

#pragma mark -
#pragma mark OPERATION COMMUNICATIONS
- (void)operationCompletedSuccessfully:(TICDSOperation *)anOperation
{
    if( [anOperation isKindOfClass:[TICDSApplicationRegistrationOperation class]] ) {
        [self applicationRegistrationOperationCompleted:(id)anOperation];
    } else if( [anOperation isKindOfClass:[TICDSListOfPreviouslySynchronizedDocumentsOperation class]] ) {
        [self listOfDocumentsOperationCompleted:(id)anOperation];
    } else if( [anOperation isKindOfClass:[TICDSWholeStoreDownloadOperation class]] ) {
        [self documentDownloadOperationCompleted:(id)anOperation];
    }
}

- (void)operationWasCancelled:(TICDSOperation *)anOperation
{
    if( [anOperation isKindOfClass:[TICDSApplicationRegistrationOperation class]] ) {
        [self applicationRegistrationOperationWasCancelled:(id)anOperation];
    } else if( [anOperation isKindOfClass:[TICDSListOfPreviouslySynchronizedDocumentsOperation class]] ) {
        [self listOfDocumentsOperationWasCancelled:(id)anOperation];
    } else if( [anOperation isKindOfClass:[TICDSWholeStoreDownloadOperation class]] ) {
        [self documentDownloadOperationWasCancelled:(id)anOperation];
    }
}

- (void)operationFailedToComplete:(TICDSOperation *)anOperation
{
    if( [anOperation isKindOfClass:[TICDSApplicationRegistrationOperation class]] ) {
        [self applicationRegistrationOperation:(id)anOperation failedToCompleteWithError:[anOperation error]];
    } else if( [anOperation isKindOfClass:[TICDSListOfPreviouslySynchronizedDocumentsOperation class]] ) {
        [self listOfDocumentsOperation:(id)anOperation failedToCompleteWithError:[anOperation error]];
    } else if( [anOperation isKindOfClass:[TICDSWholeStoreDownloadOperation class]] ) {
        [self documentDownloadOperation:(id)anOperation failedToCompleteWithError:[anOperation error]];
    }
}

#pragma mark -
#pragma mark Default Sync Manager
id gTICDSDefaultApplicationSyncManager = nil;

+ (id)defaultApplicationSyncManager
{
    if( gTICDSDefaultApplicationSyncManager ) {
        return gTICDSDefaultApplicationSyncManager;
    }
    
    gTICDSDefaultApplicationSyncManager = [[self alloc] init];
    
    return gTICDSDefaultApplicationSyncManager;
}

+ (void)setDefaultApplicationSyncManager:(TICDSApplicationSyncManager *)aSyncManager
{
    if( gTICDSDefaultApplicationSyncManager == aSyncManager ) {
        return;
    }
    
    [gTICDSDefaultApplicationSyncManager release];
    gTICDSDefaultApplicationSyncManager = [aSyncManager retain];
}

#pragma mark -
#pragma mark Paths
- (NSString *)relativePathToDocumentsDirectory
{
    return TICDSDocumentsDirectoryName;
}

- (NSString *)relativePathToClientDevicesDirectory
{
    return TICDSClientDevicesDirectoryName;
}

- (NSString *)relativePathToClientDevicesThisClientDeviceDirectory
{
    return [[self relativePathToClientDevicesDirectory] stringByAppendingPathComponent:[self clientIdentifier]];
}

- (NSString *)relativePathToDocumentDirectoryForDocumentWithIdentifier:(NSString *)anIdentifier
{
    return [[self relativePathToDocumentsDirectory] stringByAppendingPathComponent:anIdentifier];
}

- (NSString *)relativePathToWholeStoreDirectoryForDocumentWithIdentifier:(NSString *)anIdentifier
{
    return [[self relativePathToDocumentDirectoryForDocumentWithIdentifier:anIdentifier] stringByAppendingPathComponent:TICDSWholeStoreDirectoryName];
}

#pragma mark -
#pragma mark Initialization and Deallocation
- (id)init
{
    self = [super init];
    if( !self ) {
        return nil;
    }
    
    // Create Registration Queue (ready to roll)
    _registrationQueue = [[NSOperationQueue alloc] init];
    
    // Create Other Tasks Queue (suspended until registration completes)
    _otherTasksQueue = [[NSOperationQueue alloc] init];
    [_otherTasksQueue setSuspended:YES];
    
    return self;
}

- (void)dealloc
{
    [_appIdentifier release], _appIdentifier = nil;
    [_clientIdentifier release], _clientIdentifier = nil;
    [_clientDescription release], _clientDescription = nil;
    [_applicationUserInfo release], _applicationUserInfo = nil;
    [_registrationQueue release], _registrationQueue = nil;
    [_otherTasksQueue release], _otherTasksQueue = nil;
    [_fileManager release], _fileManager = nil;

    [super dealloc];
}

#pragma mark -
#pragma mark Lazy Accessors
- (NSFileManager *)fileManager
{
    if( _fileManager ) return _fileManager;
    
    _fileManager = [[NSFileManager alloc] init];
    
    return _fileManager;
}

#pragma mark -
#pragma mark Properties
@synthesize state = _state;
@synthesize delegate = _delegate;
@synthesize appIdentifier = _appIdentifier;
@synthesize clientIdentifier = _clientIdentifier;
@synthesize clientDescription = _clientDescription;
@synthesize applicationUserInfo = _applicationUserInfo;
@synthesize registrationQueue = _registrationQueue;
@synthesize otherTasksQueue = _otherTasksQueue;
@synthesize fileManager = _fileManager;

@end
