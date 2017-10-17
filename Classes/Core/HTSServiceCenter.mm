//
//  HTSServiceCenter.m
//  LiveStreaming
//
//  Created by denggang on 16/7/13.
//  Copyright © 2016年 Bytedance. All rights reserved.
//

#import "HTSServiceCenter.h"
#import <objc/runtime.h>

static HTSServiceCenter *serviceCenter = nil;

@implementation HTSService

@end

@implementation HTSServiceCenter

- (instancetype)init
{
    self = [super init];
    if(self){
        m_dicService = [[NSMutableDictionary alloc] init];
        m_lock = [[NSRecursiveLock alloc] init];
        serviceCenter = self;
    }
    return self;
}

- (void)dealloc
{
    if(m_dicService != nil){
        m_dicService = nil;
    }
    m_lock = nil;
    serviceCenter = nil;
}

#pragma mark - Public

+ (HTSServiceCenter *)defaultCenter
{
    // 由app管理本类的生命周期;
    return serviceCenter;
}

- (id)getService:(Class)cls
{
    [m_lock lock];
    id obj = [m_dicService objectForKey:cls];
    if(obj == nil) {
        
        // Service必须继承 MMService<MMService>
        if(![cls isSubclassOfClass:[HTSService class]]) {
            [m_lock unlock];
            assert(0);
            return nil;
        }
        
        if(![cls conformsToProtocol:@protocol(HTSService)]) {
            [m_lock unlock];
            assert(0);
            return nil;
        }

        obj = [[cls alloc] init];
        [m_dicService setObject:obj forKey:cls];
        [m_lock unlock];
        
        // call init
        if([obj respondsToSelector:@selector(onServiceInit)]) {
            [obj onServiceInit];
        }
    } else {
        [m_lock unlock];
    }
    
    return obj;
}

- (void)removeService:(Class)cls
{
    [m_lock lock];
    HTSService<HTSService> *obj = [m_dicService objectForKey:cls];
    
    if(obj == nil){
        [m_lock unlock];
        return ;
    }
    
    [m_dicService removeObjectForKey:cls];
    
    obj.isServiceRemoved = YES;
    [m_lock unlock];
    obj = nil;
}

- (void)callEnterForeground
{
    [m_lock lock];
    NSArray *aryCopy = [m_dicService allValues];
    [m_lock unlock];
    
    for(id obj in aryCopy) {
        if([obj respondsToSelector:@selector(onServiceEnterForeground)]) {
            [obj onServiceEnterForeground];
        }
    }
}

- (void)callEnterBackground
{
    [m_lock lock];
    NSArray *aryCopy = [m_dicService allValues];
    [m_lock unlock];
    
    for(id obj in aryCopy) {
        if ([obj respondsToSelector:@selector(onServiceEnterBackground)]) {
            [obj onServiceEnterBackground];
        }
    }
}

- (void)callTerminate
{
    [m_lock lock];
    NSArray *aryCopy = [m_dicService allValues];
    [m_lock unlock];
    
    for(id obj in aryCopy) {
        if ([obj respondsToSelector:@selector(onServiceTerminate)]) {
            [obj onServiceTerminate];
        }
    }
}

- (void)callServiceMemoryWarning
{
    [m_lock lock];
    NSArray *aryCopy = [m_dicService allValues];
    [m_lock unlock];
    
    for(id obj in aryCopy) {
        if([obj respondsToSelector:@selector(onServiceMemoryWarning)]) {
            [obj onServiceMemoryWarning];
        }
    }
}

- (void)callClearData
{
    [m_lock lock];
    NSArray *aryCopy = [m_dicService allValues];
    [m_lock unlock];
    
    for(HTSService<HTSService> *obj in aryCopy) {
        if([obj respondsToSelector:@selector(onServiceClearData)]) {
            [obj onServiceClearData];
        }
        
        if(obj.isServicePersistent == NO) {
            // remove
            [self removeService:[obj class]];
        }
    }
}


@end
