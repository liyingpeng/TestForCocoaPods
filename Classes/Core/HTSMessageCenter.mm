//
//  HTSMessageCenter.m
//  LiveStreaming
//
//  Created by denggang on 16/7/13.
//  Copyright © 2016年 Bytedance. All rights reserved.
//

#import "HTSMessageCenter.h"
#import <objc/runtime.h>
#import <vector>
#import <pthread.h>

// 每 5min 清理一次
#define MESSAGE_CLEAN_TIME (5*60)

@implementation HTSMessageObject

- (void)setObject:(CFTypeRef)Obj
{
    //没有增加引用计数
    m_Obj = Obj;
}

- (CFTypeRef)getObject
{
    return m_Obj;
}

- (BOOL)isObjectEqual:(CFTypeRef)Obj
{
    if (_m_deleteMark == YES) {
        return NO;
    }
    
    if (m_Obj == Obj) {
        return YES;
    }
    
    return NO;
}

- (id)initWithObject:(CFTypeRef)Obj
{
    if (self = [super init]) {
        _m_deleteMark = NO;
        [self setObject:Obj];
    }
    return self;
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"<%@-deleteMark[%d]>",m_Obj, _m_deleteMark];
}

@end

@implementation HTSMessageDictionary

- (instancetype)init
{
    if (self = [super init]) {
        m_dic = [[NSMutableDictionary alloc] init];
        m_needCleanUp = NO;
    }
    return self;
}

- (void)dealloc
{
    m_dic = nil;
}

- (BOOL)registerMessage:(id) oObserver forKey:(id) nsKey
{
    if (oObserver == nil || nsKey == nil) {
        assert(0);
        return NO;
    }
    
    NSMutableArray *selectorImplememters = [m_dic objectForKey:nsKey];
    if (selectorImplememters == nil) {
        selectorImplememters = [[NSMutableArray alloc] init];
        [m_dic setObject:selectorImplememters forKey:nsKey];
    }
    
    for(HTSMessageObject *messageObj in selectorImplememters) {
        if ([messageObj isObjectEqual:(__bridge  CFTypeRef)oObserver]) {
            return NO;
        }
    }
    
    HTSMessageObject *messageObj = [[HTSMessageObject alloc] initWithObject:(__bridge CFTypeRef)oObserver];
    [selectorImplememters addObject:messageObj];
    
    return YES;
}

- (BOOL)unregisterMessage:(id) oObserver forKey:(id) nsKey
{
    if (oObserver == nil /*|| nsKey == nil*/) {
        assert(0);
        return NO;
    }
    
    NSArray *ary = [m_dic objectForKey:nsKey];
    for(HTSMessageObject *messageObj in ary) {
        if (messageObj.m_deleteMark == NO && [messageObj getObject] == (__bridge CFTypeRef)oObserver) {
            messageObj.m_deleteMark = YES;
            m_needCleanUp = YES;
            return YES;
        }
    }
    return NO;
}

- (BOOL)unregisterKeyMessage:(id)oObserver
{
    BOOL bFound = NO;
    
    for(NSArray *selectorImplememters in [m_dic allValues]) {
        for(HTSMessageObject *messageObj in selectorImplememters) {
            if (messageObj.m_deleteMark == NO && [messageObj getObject] == (__bridge CFTypeRef)oObserver) {
                messageObj.m_deleteMark = YES;
                bFound = YES;
                break;
            }
        }
    }
    
    if (bFound) {
        m_needCleanUp = YES;
    }
    return bFound;
}

- (NSArray *)getKeyMessageList:(id)nsKey
{
    return [m_dic objectForKey:nsKey];
}

- (void)cleanUp
{
    if (!m_needCleanUp) {
        return;
    }
    m_needCleanUp = NO;
    
    for (id oKey in [m_dic allKeys]) {
        NSMutableArray *arrMessage = [m_dic objectForKey:oKey];
        NSMutableIndexSet *delIndexSet = [[NSMutableIndexSet alloc] init];
        for(NSInteger index = 0; index < arrMessage.count;index++) {
            HTSMessageObject *messageObj = [arrMessage objectAtIndex:index];
            if (messageObj.m_deleteMark) {
                [delIndexSet addIndex:index];
            }
        }
        
        [arrMessage removeObjectsAtIndexes:delIndexSet];
        
        if (arrMessage.count == 0) {
            [m_dic removeObjectForKey:oKey];
        }
    }
}

@end


@implementation HTSMessage
{
    pthread_mutex_t lock;
}

- (instancetype)initWithKey:( HTSMessageKey)oKey
{
    self = [super init];
    if(self) {
        pthread_mutex_init(&lock, NULL);
        
        m_dicObserver = nil;
        m_dicKeyObserver = nil;
        m_messageKey = oKey;
        
        // copy all selectors
        std::vector<objc_method_description> arrMethods = [self getAllMethodOfProtocol:oKey];
        m_methodCount = (unsigned int)arrMethods.size();
        
        if (m_methodCount > 0) {
            m_methods = new objc_method_description[m_methodCount];
            std::copy(arrMethods.begin(), arrMethods.end(), m_methods);
        }
    }
    return self;
}

- (void)dealloc
{
    m_dicObserver = nil;
    m_dicKeyObserver = nil;
    if (m_methods != NULL) {
        delete []m_methods;
        m_methods = NULL;
    }
    
    pthread_mutex_destroy(&lock);
}

- (BOOL)registerMessage:(id)oObserver
{
    if ([oObserver conformsToProtocol:m_messageKey] == NO) {
        return NO;
    }
    
    pthread_mutex_lock(&lock);
    
    if (m_dicObserver == nil) {
        m_dicObserver = [[HTSMessageDictionary alloc] init];
    }
    
    Class cls = [oObserver class];
    for (unsigned int index = 0; index < m_methodCount; index++) {
        objc_method_description *method = &m_methods[index];
        
        if (class_respondsToSelector(cls, method->name)) {
            [m_dicObserver registerMessage:oObserver forKey:NSStringFromSelector(method->name)];
        }
    }
    
    pthread_mutex_unlock(&lock);
    
    return YES;
}

- (BOOL)registerMessage:(id)oObserver forKey:(id)nsKey
{
    if ([oObserver conformsToProtocol:m_messageKey] == NO) {
        return NO;
    }
    
    pthread_mutex_lock(&lock);
    
    if (m_dicKeyObserver == nil) {
        m_dicKeyObserver = [[HTSMessageDictionary alloc] init];
    }
    
    [m_dicKeyObserver registerMessage:oObserver forKey:nsKey];
    
    pthread_mutex_unlock(&lock);
    
    return YES;
}

- (void)unregisterMessage:(id) oObserver
{
    pthread_mutex_lock(&lock);
    [m_dicObserver unregisterKeyMessage:oObserver];
    pthread_mutex_unlock(&lock);
}

- (void)unregisterMessage:(id) oObserver forKey:(id) nsKey
{
    pthread_mutex_lock(&lock);
    [m_dicKeyObserver unregisterMessage:oObserver forKey:nsKey];
    pthread_mutex_unlock(&lock);
}

- (void)unregisterKeyMessage:(id)oObserver
{
    pthread_mutex_lock(&lock);
    [m_dicKeyObserver unregisterKeyMessage:oObserver];
    pthread_mutex_unlock(&lock);
}

- (NSArray *)getMessageListForSelector:(SEL)selector
{
    return [m_dicObserver getKeyMessageList:NSStringFromSelector(selector)];
}

- (NSArray *)getKeyMessageList:(id) nsKey
{
    return [m_dicKeyObserver getKeyMessageList:nsKey];
}

- (void)cleanUp
{
    pthread_mutex_lock(&lock);
    [m_dicObserver cleanUp];
    [m_dicKeyObserver cleanUp];
    pthread_mutex_unlock(&lock);
}

- (NSString *)description 
{
    return [NSString stringWithFormat:@"%@ => {\n%@,\nkey_message:\n%@\n}",NSStringFromProtocol(m_messageKey),m_dicObserver,m_dicKeyObserver];
}

#pragma mark - Private

- (std::vector<objc_method_description>)getAllMethodOfProtocol:(Protocol*) proto
{
    std::vector<objc_method_description> arrMethos;
    getAllMethodForProtocol(proto, arrMethos);
    return arrMethos;
}

static void getAllMethodForProtocol(HTSMessageKey proto, std::vector<objc_method_description>& arrMethods)
{
    //<NSObject>就不处理了
    if (protocol_isEqual(proto, @protocol(NSObject))) {
        return;
    }
    
    unsigned int protoCount = 0;
    HTSMessageKey __unsafe_unretained *arrProto = protocol_copyProtocolList(proto, &protoCount);
    if (arrProto != NULL && protoCount > 0) {
        for (unsigned int index = 0; index < protoCount; index++) {
            getAllMethodForProtocol(arrProto[index], arrMethods);
        }
        free(arrProto);
    }
    
    unsigned int optionalCount = 0;
    objc_method_description* optionalMethods = protocol_copyMethodDescriptionList(proto, NO, YES, &optionalCount);
    if (optionalMethods != NULL && optionalCount > 0) {
        arrMethods.insert(arrMethods.end(), optionalMethods, optionalMethods+optionalCount);
        free(optionalMethods);
    }
    
    unsigned int requiredCount = 0;
    objc_method_description* requiredMethods = protocol_copyMethodDescriptionList(proto, YES, YES, &requiredCount);
    if (requiredMethods != NULL && requiredCount > 0) {
        arrMethods.insert(arrMethods.end(), requiredMethods, requiredMethods+requiredCount);
        free(requiredMethods);
    }
}

@end

@implementation HTSMessageCenter
{
    pthread_mutex_t lock;
}

- (id) init
{
    if(self = [super init]) {
        pthread_mutex_init(&lock, NULL);
        //
        self.isServicePersistent = YES;
        m_dicMessage = [[NSMutableDictionary alloc] init];
        
        [self performSelector:@selector(cleanUp) withObject:nil afterDelay:MESSAGE_CLEAN_TIME];
    }
    return self;
}

- (void)dealloc
{
    if (m_dicMessage) {
        m_dicMessage = nil;
    }
    
    pthread_mutex_destroy(&lock);
}

- (HTSMessage *)getMessage:(HTSMessageKey) oKey
{
    HTSMessage *message = nil;
    
    pthread_mutex_lock(&lock);
    //
    NSString *key = NSStringFromProtocol(oKey);
    message = [m_dicMessage objectForKey:key];
    if (message == nil) {
        message = [[HTSMessage alloc] initWithKey:oKey];
        [m_dicMessage setObject:message forKey:key];
    }
    //
    pthread_mutex_unlock(&lock);
    
    return message;
}

- (void)cleanUp
{
    // HTSMessage = nil 的保护
    [m_dicMessage enumerateKeysAndObjectsUsingBlock:^(id  _Nonnull key, id  _Nonnull obj, BOOL * _Nonnull stop) {
        HTSMessage *message = (HTSMessage *)obj;
        [message cleanUp];
    }];
    
    [self performSelector:@selector(cleanUp) withObject:nil afterDelay:MESSAGE_CLEAN_TIME];
}

@end
