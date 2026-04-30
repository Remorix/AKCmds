#pragma once

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface ClassHierarchy : NSObject

- (instancetype)init;
- (nullable instancetype)initWithFile:(NSString *)path;

- (nullable NSString *)superclassOfClass:(NSString *)className;
- (void)setSuperclass:(nullable NSString *)superclassName forClass:(NSString *)className;
- (void)removeSuperclassForClass:(NSString *)className;
- (void)renameClass:(NSString *)oldName toName:(NSString *)newName;

- (BOOL)class:(NSString *)className descendsFrom:(NSString *)ancestorName;
- (NSEnumerator *)classEnumerator;
- (BOOL)writeToFile:(NSString *)path;

@end

NS_ASSUME_NONNULL_END
