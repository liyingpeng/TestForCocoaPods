//
//  HTSMessageCenter.h
//  LiveStreaming
//
//  Created by denggang on 16/7/13.
//  Copyright © 2016年 Bytedance. All rights reserved.
//


/*
 * 消息中心：
       一系列的消息，每个消息是一个协议（protocol）；
       消息接收者，即为协议的实现者；
       消息的发送者和接收者都不知道对方的存在；
       是一个特殊的服务对象；
   使用方法：
       1、注册接收消息：REGISTER_MESSAGE（xxxMessage, self）
       2、要有配对的取消注册接收消息：UNREGISTER_MESSAGE（xxxMessage, self），必须有！！！
       3、产生消息：SAFECALL_MESSAGE(xxxMessage, xxx:xxx);
       4、消息的协议函数中处理事件
   命名：
      所有消息的命名，xxxMessage，以Message结尾
 */

typedef Protocol *HTSMessageKey;

struct objc_method_description;

#import <UIKit/UIKit.h>
#import "HTSServiceCenter.h"


/*
 *   REGISTER_MESSAGE后，关注者会被引用，而一般在关注者析构时才会UNREGISTER_MESSAGE。
     但因为被引用了，没办法掉到析构。
     所以引入HTSMessageObject， 不再对关注者加引用。但带来其他问题：
     如果关注者忘记UNREGISTER_MESSAGE， 则会crash。
 */
@interface HTSMessageObject : NSObject
{
    CFTypeRef m_Obj;
}

@property(nonatomic, assign)BOOL m_deleteMark;

- (void)setObject:(CFTypeRef)Obj;
- (CFTypeRef)getObject;
- (BOOL)isObjectEqual:(CFTypeRef) Obj;

@end

@interface HTSMessageDictionary : NSObject
{
    NSMutableDictionary *m_dic;
    BOOL m_needCleanUp;
}

- (BOOL)registerMessage:(id)oObserver forKey:(id)nsKey;
- (BOOL)unregisterMessage:(id)oObserver forKey:(id)nsKey;
- (BOOL)unregisterKeyMessage:(id)oObserver;
- (NSArray *)getKeyMessageList:(id)nsKey;

- (void)cleanUp;

@end

/* 
 * 对protocol中的每个函数，都储存了所有注册监听它的observer，集中分发
 
 Message. keep observer list.
 1.  Message -> Observer list
 2. (Message, key) -> Observer List.
	key一般用NSString
 */
@interface HTSMessage : NSObject
{
    // protocl
    HTSMessageKey m_messageKey;
    
    // selector
    unsigned int m_methodCount;
    struct objc_method_description *m_methods;
    
    // selector -> array(HTSMessageObject)
    HTSMessageDictionary *m_dicObserver;
    
    // key -> array(HTSMessageObject)
    HTSMessageDictionary *m_dicKeyObserver;
}

- (instancetype)initWithKey:(HTSMessageKey)oKey;
- (BOOL)registerMessage:(id)oObserver;
- (void)unregisterMessage:(id)oObserver;
- (NSArray *)getMessageListForSelector:(SEL)selector;

- (BOOL)registerMessage:(id)oObserver forKey:(id)nsKey;
- (void)unregisterMessage:(id)oObserver forKey:(id)nsKey;
- (void)unregisterKeyMessage:(id)oObserver;
- (NSArray *)getKeyMessageList:(id)nsKey;

// 为了效率考虑（不每次SAFE_CALL都新建一个NSArray），延迟清理unreg
- (void)cleanUp;

@end

@interface HTSMessageCenter : HTSService <HTSService>
{
    // map(HTSMessageKey -> HTSMessage)
    NSMutableDictionary *m_dicMessage;
}

- (HTSMessage *)getMessage:(HTSMessageKey)key;

@end


#define REGISTER_MESSAGE(message, obj)	\
{ \
    HTSMessage *__oMessage__ = [GET_SERVICE(HTSMessageCenter) getMessage:@protocol(message)]; \
    if (__oMessage__) { \
        [__oMessage__ registerMessage:obj]; \
    } \
}

#define UNREGISTER_MESSAGE(message, obj)	\
{ \
    HTSMessage *__oMessage__ = [GET_SERVICE(HTSMessageCenter) getMessage:@protocol(message)]; \
    if (__oMessage__) { \
        [__oMessage__ unregisterMessage:obj]; \
    }\
}

#define SAFECALL_MESSAGE(message, sel, func)	\
{ \
    HTSMessage *__oMessage__ = [GET_SERVICE(HTSMessageCenter) getMessage:@protocol(message)]; \
    if (__oMessage__) { \
        NSArray *__ary__ = [__oMessage__ getMessageListForSelector:sel]; \
        for(UInt32 __index__ = 0; __index__ < __ary__.count; __index__++) { \
            HTSMessageObject *__obj__ = [__ary__ objectAtIndex:__index__]; \
            if(__obj__.m_deleteMark == YES)continue; \
            NSObject<message>* __oMessageObj__ = (__bridge NSObject<message>*)[__obj__ getObject]; \
            [__oMessageObj__ func]; \
        } \
    } \
}

#define THREAD_SAFECALL_MESSAGE(message, sel, func) \
{ \
    if ([NSThread isMainThread]) { \
        SAFECALL_MESSAGE(message, sel, func); \
    } else { \
        dispatch_sync(dispatch_get_main_queue(), ^{ \
            SAFECALL_MESSAGE(message, sel, func); \
        }); \
    } \
}

#define REGISTER_KEY_MESSAGE(message, key, obj) \
{ \
    HTSMessage *__oMessage__ = [GET_SERVICE(HTSMessageCenter) getMessage:@protocol(message)]; \
    if (__oMessage__) { \
        [__oMessage__ registerMessage:obj forKey:key]; \
    } \
}

#define UNREGISTER_KEY_MESSAGE(message, key, obj)	\
{ \
    HTSMessage *__oMessage__ = [GET_SERVICE(HTSMessageCenter) getMessage:@protocol(message)]; \
    if (__oMessage__) { \
        [__oMessage__ unregisterMessage:obj forKey:key]; \
    } \
}

#define UNREGISTER_ALL_KEY_MESSAGE(message, obj) \
{ \
    HTSMessage *__oMessage__ = [GET_SERVICE(HTSMessageCenter) getMessage:@protocol(message)]; \
    if (__oMessage__) { \
        [__oMessage__ unregisterKeyMessage:obj]; } \
}

#define SAFECALL_KEY_MESSAGE(message, key, sel, func)	\
{ \
    HTSMessage *__oMessage__ = [GET_SERVICE(HTSMessageCenter) getMessage:@protocol(message)]; \
    if (__oMessage__) { \
        NSArray *__ary__ = [__oMessage__ getKeyMessageList:key]; \
        for(UInt32 __index__ = 0; __index__ < __ary__.count; __index__++) { \
            HTSMessageObject *__obj__ = [__ary__ objectAtIndex:__index__]; \
                if(__obj__.m_deleteMark == YES)continue; \
                NSObject<message>* __oMessageObj__ =  (__bridge NSObject<message>*)[__obj__ getObject]; \
                if ([__oMessageObj__ respondsToSelector:sel]) { \
                    [__oMessageObj__ func]; \
                } \
        } \
    } \
}

#define THREAD_SAFECALL_KEY_MESSAGE(message, key, sel, func) \
{ \
    if ([NSThread isMainThread]) { \
        SAFECALL_KEY_MESSAGE(message, key, sel, func); \
    } else { \
        dispatch_sync(dispatch_get_main_queue(), ^{ \
            SAFECALL_KEY_MESSAGE(message, key, sel, func); \
        }); \
    } \
}