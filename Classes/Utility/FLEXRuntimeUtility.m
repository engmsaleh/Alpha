//
//  FLEXRuntimeUtility.m
//  Flipboard
//
//  Created by Ryan Olson on 6/8/14.
//  Copyright (c) 2014 Flipboard. All rights reserved.
//

#import "FLEXRuntimeUtility.h"

// See https://developer.apple.com/library/ios/documentation/Cocoa/Conceptual/ObjCRuntimeGuide/Articles/ocrtPropertyIntrospection.html#//apple_ref/doc/uid/TP40008048-CH101-SW6
static NSString *const kFLEXUtilityAttributeTypeEncoding = @"T";
static NSString *const kFLEXUtilityAttributeBackingIvar = @"V";
static NSString *const kFLEXUtilityAttributeReadOnly = @"R";
static NSString *const kFLEXUtilityAttributeCopy = @"C";
static NSString *const kFLEXUtilityAttributeRetain = @"&";
static NSString *const kFLEXUtilityAttributeNonAtomic = @"N";
static NSString *const kFLEXUtilityAttributeCustomGetter = @"G";
static NSString *const kFLEXUtilityAttributeCustomSetter = @"S";
static NSString *const kFLEXUtilityAttributeDynamic = @"D";
static NSString *const kFLEXUtilityAttributeWeak = @"W";
static NSString *const kFLEXUtilityAttributeGarbageCollectable = @"P";
static NSString *const kFLEXUtilityAttributeOldStyleTypeEncoding = @"t";

static NSString *const FLEXRuntimeUtilityErrorDomain = @"FLEXRuntimeUtilityErrorDomain";
typedef NS_ENUM(NSInteger, FLEXRuntimeUtilityErrorCode) {
    FLEXRuntimeUtilityErrorCodeDoesNotRecognizeSelector = 0,
    FLEXRuntimeUtilityErrorCodeInvocationFailed = 1
};

// Arguments 0 and 1 are self and _cmd always
const unsigned int kFLEXNumberOfImplicitArgs = 2;

@implementation FLEXRuntimeUtility


#pragma mark - Property Helpers (Public)

+ (NSString *)prettyNameForProperty:(objc_property_t)property
{
    NSString *name = @(property_getName(property));
    NSString *encoding = [self typeEncodingForProperty:property];
    NSString *readableType = [self readableTypeForEncoding:encoding];
    return [self appendName:name toType:readableType];
}

+ (NSString *)typeEncodingForProperty:(objc_property_t)property
{
    NSDictionary *attributesDictionary = [self attributesDictionaryForProperty:property];
    return [attributesDictionary objectForKey:kFLEXUtilityAttributeTypeEncoding];
}

+ (BOOL)isReadonlyProperty:(objc_property_t)property
{
    return [[self attributesDictionaryForProperty:property] objectForKey:kFLEXUtilityAttributeReadOnly] != nil;
}

+ (SEL)setterSelectorForProperty:(objc_property_t)property
{
    SEL setterSelector = NULL;
    NSString *setterSelectorString = [[self attributesDictionaryForProperty:property] objectForKey:kFLEXUtilityAttributeCustomSetter];
    if (!setterSelectorString) {
        NSString *propertyName = @(property_getName(property));
        setterSelectorString = [NSString stringWithFormat:@"set%@%@:", [[propertyName substringToIndex:1] uppercaseString], [propertyName substringFromIndex:1]];
    }
    if (setterSelectorString) {
        setterSelector = NSSelectorFromString(setterSelectorString);
    }
    return setterSelector;
}

+ (NSString *)fullDescriptionForProperty:(objc_property_t)property
{
    NSDictionary *attributesDictionary = [self attributesDictionaryForProperty:property];
    NSMutableArray *attributesStrings = [NSMutableArray array];
    
    // Atomicity
    if ([attributesDictionary objectForKey:kFLEXUtilityAttributeNonAtomic]) {
        [attributesStrings addObject:@"nonatomic"];
    } else {
        [attributesStrings addObject:@"atomic"];
    }
    
    // Storage
    if ([attributesDictionary objectForKey:kFLEXUtilityAttributeRetain]) {
        [attributesStrings addObject:@"strong"];
    } else if ([attributesDictionary objectForKey:kFLEXUtilityAttributeCopy]) {
        [attributesStrings addObject:@"copy"];
    } else if ([attributesDictionary objectForKey:kFLEXUtilityAttributeWeak]) {
        [attributesStrings addObject:@"weak"];
    } else {
        [attributesStrings addObject:@"assign"];
    }
    
    // Mutability
    if ([attributesDictionary objectForKey:kFLEXUtilityAttributeReadOnly]) {
        [attributesStrings addObject:@"readonly"];
    } else {
        [attributesStrings addObject:@"readwrite"];
    }
    
    // Custom getter/setter
    NSString *customGetter = [attributesDictionary objectForKey:kFLEXUtilityAttributeCustomGetter];
    NSString *customSetter = [attributesDictionary objectForKey:kFLEXUtilityAttributeCustomSetter];
    if (customGetter) {
        [attributesStrings addObject:[NSString stringWithFormat:@"getter=%@", customGetter]];
    }
    if (customSetter) {
        [attributesStrings addObject:[NSString stringWithFormat:@"setter=%@", customSetter]];
    }
    
    NSString *attributesString = [attributesStrings componentsJoinedByString:@", "];
    NSString *shortName = [self prettyNameForProperty:property];
    
    return [NSString stringWithFormat:@"@property (%@) %@", attributesString, shortName];
}

+ (id)valueForProperty:(objc_property_t)property onObject:(id)object
{
    NSString *customGetterString = nil;
    char *customGetterName = property_copyAttributeValue(property, "G");
    if (customGetterName) {
        customGetterString = @(customGetterName);
        free(customGetterName);
    }
    
    SEL getterSelector;
    if ([customGetterString length] > 0) {
        getterSelector = NSSelectorFromString(customGetterString);
    } else {
        NSString *propertyName = @(property_getName(property));
        getterSelector = NSSelectorFromString(propertyName);
    }
    
    return [self performSelector:getterSelector onObject:object withArguments:nil error:NULL];
}

+ (NSString *)descriptionForIvarOrPropertyValue:(id)value
{
    NSString *description = nil;
    
    // Special case BOOL for better readability.
    if ([value isKindOfClass:[NSValue class]]) {
        const char *type = [value objCType];
        if (strcmp(type, @encode(BOOL)) == 0) {
            BOOL boolValue = NO;
            [value getValue:&boolValue];
            description = boolValue ? @"YES" : @"NO";
        }
    }
    
    if (!description) {
        // Single line display - replace newlines and tabs with spaces.
        description = [[value description] stringByReplacingOccurrencesOfString:@"\n" withString:@" "];
        description = [description stringByReplacingOccurrencesOfString:@"\t" withString:@" "];
    }
    
    if (!description) {
        description = @"nil";
    }
    
    return description;
}


#pragma mark - Ivar Helpers (Public)

+ (NSString *)prettyNameForIvar:(Ivar)ivar
{
    NSString *name = @(ivar_getName(ivar));
    NSString *encoding = @(ivar_getTypeEncoding(ivar));
    NSString *readableType = [self readableTypeForEncoding:encoding];
    return [self appendName:name toType:readableType];
}

+ (id)valueForIvar:(Ivar)ivar onObject:(id)object
{
    id value = nil;
    const char *type = ivar_getTypeEncoding(ivar);
    if (type[0] == @encode(id)[0] || type[0] == @encode(Class)[0]) {
        value = object_getIvar(object, ivar);
    } else {
        ptrdiff_t offset = ivar_getOffset(ivar);
        void *pointer = (__bridge void *)object + offset;
        value = [self valueForPrimitivePointer:pointer objcType:type];
    }
    return value;
}

+ (void)setIvar:(Ivar)ivar onObject:(id)object withInputString:(NSString *)inputString
{
    const char *typeEncodingCString = ivar_getTypeEncoding(ivar);
    if (typeEncodingCString[0] == '@') {
        // Object - use NSJSONSerialization
        id ivarValue = [self objectValueFromEditableString:inputString];
        object_setIvar(object, ivar, ivarValue);
    } else {
        // Primitive - try to parse a number or struct from the string based on the type encoding
        NSUInteger bufferSize = 0;
        NSGetSizeAndAlignment(typeEncodingCString, &bufferSize, NULL);
        void *buffer = malloc(bufferSize);
        [self getPrimitiveValue:buffer withObjCType:typeEncodingCString fromInputString:inputString];
        ptrdiff_t offset = ivar_getOffset(ivar);
        void *pointer = (__bridge void *)object + offset;
        memcpy(pointer, buffer, bufferSize);
    }
}


#pragma mark - Method Helpers (Public)

+ (NSString *)prettyNameForMethod:(Method)method isClassMethod:(BOOL)isClassMethod
{
    NSString *selectorName = NSStringFromSelector(method_getName(method));
    NSString *methodTypeString = isClassMethod ? @"+" : @"-";
    char *returnType = method_copyReturnType(method);
    NSString *readableReturnType = [self readableTypeForEncoding:@(returnType)];
    free(returnType);
    NSString *prettyName = [NSString stringWithFormat:@"%@ (%@)", methodTypeString, readableReturnType];
    NSArray *components = [self prettyArgumentComponentsForMethod:method];
    if ([components count] > 0) {
        prettyName = [prettyName stringByAppendingString:[components componentsJoinedByString:@" "]];
    } else {
        prettyName = [prettyName stringByAppendingString:selectorName];
    }
    
    return prettyName;
}

+ (NSArray *)prettyArgumentComponentsForMethod:(Method)method
{
    NSMutableArray *components = [NSMutableArray array];
    
    NSString *selectorName = NSStringFromSelector(method_getName(method));
    NSArray *selectorComponents = [selectorName componentsSeparatedByString:@":"];
    unsigned int numberOfArguments = method_getNumberOfArguments(method);
    
    for (unsigned int argIndex = kFLEXNumberOfImplicitArgs; argIndex < numberOfArguments; argIndex++) {
        char *argType = method_copyArgumentType(method, argIndex);
        NSString *readableArgType = [self readableTypeForEncoding:@(argType)];
        free(argType);
        NSString *prettyComponent = [NSString stringWithFormat:@"%@:(%@) ", [selectorComponents objectAtIndex:argIndex - kFLEXNumberOfImplicitArgs], readableArgType];
        [components addObject:prettyComponent];
    }
    
    return components;
}


#pragma mark - Method Calling/Field Editing (Public)

+ (id)performSelector:(SEL)selector onObject:(id)object withArguments:(NSArray *)arguments error:(NSError * __autoreleasing *)error
{
    // Bail if the object won't respond to this selector.
    if (![object respondsToSelector:selector]) {
        if (error) {
            NSDictionary *userInfo = @{ NSLocalizedDescriptionKey : [NSString stringWithFormat:@"%@ does not respond to the selector %@", object, NSStringFromSelector(selector)]};
            *error = [NSError errorWithDomain:FLEXRuntimeUtilityErrorDomain code:FLEXRuntimeUtilityErrorCodeDoesNotRecognizeSelector userInfo:userInfo];
        }
        return nil;
    }
    
    // Build the invocation
    NSMethodSignature *methodSignature = [object methodSignatureForSelector:selector];
    NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:methodSignature];
    [invocation setSelector:selector];
    [invocation setTarget:object];
    [invocation retainArguments];
    
    // Always self and _cmd
    NSUInteger numberOfArguments = [methodSignature numberOfArguments];
    for (NSUInteger argumentIndex = kFLEXNumberOfImplicitArgs; argumentIndex < numberOfArguments; argumentIndex++) {
        NSUInteger argumentsArrayIndex = argumentIndex - kFLEXNumberOfImplicitArgs;
        NSString *argumentString = [arguments count] > argumentsArrayIndex ? [arguments objectAtIndex:argumentsArrayIndex] : nil;
        const char *typeEncodingCString = [methodSignature getArgumentTypeAtIndex:argumentIndex];
        if (typeEncodingCString[0] == @encode(id)[0] || typeEncodingCString[0] == @encode(Class)[0]) {
            // Object
            id argumentObject = [self objectValueFromEditableString:argumentString];
            [invocation setArgument:&argumentObject atIndex:argumentIndex];
        } else if (strcmp(typeEncodingCString, @encode(const char *)) == 0 || strcmp(typeEncodingCString, @encode(char *)) == 0) {
            // C string
            const char *argumentCString = [argumentString UTF8String];
            [invocation setArgument:&argumentCString atIndex:argumentIndex];
        } else {
            // Primitive number or struct
            NSUInteger bufferSize = 0;
            NSGetSizeAndAlignment(typeEncodingCString, &bufferSize, NULL);
            void *buffer = malloc(bufferSize);
            [self getPrimitiveValue:buffer withObjCType:typeEncodingCString fromInputString:argumentString];
            [invocation setArgument:buffer atIndex:argumentIndex];
            free(buffer);
        }
    }
    
    // Try to invoke the invocation but guard against an exception being thrown.
    BOOL successfullyInvoked = NO;
    @try {
        // Some methods are not fit to be called...
        // Looking at you -[UIResponder(UITextInputAdditions) _caretRect]
        [invocation invoke];
        successfullyInvoked = YES;
    } @catch (NSException *exception) {
        // Bummer...
        if (error) {
            NSDictionary *userInfo = @{ NSLocalizedDescriptionKey : [NSString stringWithFormat:@"Exception thrown while performing selector %@ on object %@", object, NSStringFromSelector(selector)]};
            *error = [NSError errorWithDomain:FLEXRuntimeUtilityErrorDomain code:FLEXRuntimeUtilityErrorCodeInvocationFailed userInfo:userInfo];
        }
    }
    
    // Retreive the return value and box if necessary.
    id returnObject = nil;
    if (successfullyInvoked) {
        const char *returnType = [methodSignature methodReturnType];
        if (returnType[0] == @encode(id)[0] || returnType[0] == @encode(Class)[0]) {
            __unsafe_unretained id objectReturnedFromMethod = nil;
            [invocation getReturnValue:&objectReturnedFromMethod];
            returnObject = objectReturnedFromMethod;
        } else if (returnType[0] != @encode(void)[0]) {
            void *returnValue = malloc([methodSignature methodReturnLength]);
            if (returnValue) {
                [invocation getReturnValue:returnValue];
                returnObject = [self valueForPrimitivePointer:returnValue objcType:returnType];
                free(returnValue);
            }
        }
    }
    
    return returnObject;
}

+ (NSString *)editiableDescriptionForObject:(id)object
{
    NSString *editableDescription = nil;
    
    if ([object isKindOfClass:[NSValue class]]) {
        NSValue *value = (NSValue *)object;
        const char *typeEncoding = [value objCType];
        if (strcmp(typeEncoding, @encode(CGRect)) == 0) {
            editableDescription = NSStringFromCGRect([value CGRectValue]);
        } else if (strcmp(typeEncoding, @encode(CGSize)) == 0) {
            editableDescription = NSStringFromCGSize([value CGSizeValue]);
        } else if (strcmp(typeEncoding, @encode(CGPoint)) == 0) {
            editableDescription = NSStringFromCGPoint([value CGPointValue]);
        } else if (strcmp(typeEncoding, @encode(CGAffineTransform)) == 0) {
            editableDescription = NSStringFromCGAffineTransform([value CGAffineTransformValue]);
        } else if (strcmp(typeEncoding, @encode(NSRange)) == 0) {
            editableDescription = NSStringFromRange([value rangeValue]);
        } else if (strcmp(typeEncoding, @encode(UIEdgeInsets)) == 0) {
            editableDescription = NSStringFromUIEdgeInsets([value UIEdgeInsetsValue]);
        } else if (strcmp(typeEncoding, @encode(UIOffset)) == 0) {
            editableDescription = NSStringFromUIOffset([value UIOffsetValue]);
        }
    }
    
    if (object && !editableDescription) {
        // This is a hack to use JSON serialzation for our editable objects.
        // NSJSONSerialization doesn't allow writing fragments - the top level object must be an array or dictionary.
        // We always wrap the object inside an array and then strip the outter square braces off the final string.
        NSArray *wrappedObject = @[object];
        if ([NSJSONSerialization isValidJSONObject:wrappedObject]) {
            NSString *wrappedDescription = [[NSString alloc] initWithData:[NSJSONSerialization dataWithJSONObject:wrappedObject options:0 error:NULL] encoding:NSUTF8StringEncoding];
            editableDescription = [wrappedDescription substringWithRange:NSMakeRange(1, [wrappedDescription length] - 2)];
        }
    }
    
    return editableDescription;
}

+ (id)objectValueFromEditableString:(NSString *)string
{
    id value = nil;
    // nil for empty string/whitespace
    if ([[string stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] length] > 0) {
        value = [NSJSONSerialization JSONObjectWithData:[string dataUsingEncoding:NSUTF8StringEncoding] options:NSJSONReadingAllowFragments error:NULL];
    }
    return value;
}


#pragma mark - Internal Helpers

+ (NSDictionary *)attributesDictionaryForProperty:(objc_property_t)property
{
    NSString *attributes = @(property_getAttributes(property));
    // Thanks to MAObjcRuntime for inspiration here.
    NSArray *attributePairs = [attributes componentsSeparatedByString:@","];
    NSMutableDictionary *attributesDictionary = [NSMutableDictionary dictionaryWithCapacity:[attributePairs count]];
    for (NSString *attributePair in attributePairs) {
        [attributesDictionary setObject:[attributePair substringFromIndex:1] forKey:[attributePair substringToIndex:1]];
    }
    return attributesDictionary;
}

+ (NSString *)appendName:(NSString *)name toType:(NSString *)type
{
    NSString *combined = nil;
    if ([type characterAtIndex:[type length] - 1] == '*') {
        combined = [type stringByAppendingString:name];
    } else {
        combined = [type stringByAppendingFormat:@" %@", name];
    }
    return combined;
}

+ (NSString *)readableTypeForEncoding:(NSString *)encodingString
{
    // See https://developer.apple.com/library/mac/#documentation/Cocoa/Conceptual/ObjCRuntimeGuide/Articles/ocrtTypeEncodings.html
    // class-dump has a much nicer and much more complete implementation for this task, but it is distributed under GPLv2 :/
    // See https://github.com/nygard/class-dump/blob/master/Source/CDType.m
    // Warning: this method uses multiple middle returns and macros to cut down on boilerplate.
    // The use of macros here was inspired by https://www.mikeash.com/pyblog/friday-qa-2013-02-08-lets-build-key-value-coding.html
    const char *encodingCString = [encodingString UTF8String];
    
    // Objects
    if (encodingCString[0] == '@') {
        NSString *class = [encodingString substringFromIndex:1];
        class = [class stringByReplacingOccurrencesOfString:@"\"" withString:@""];
        if ([class length] == 0) {
            class = @"id";
        } else {
            class = [class stringByAppendingString:@" *"];
        }
        return class;
    }
    
    // C Types
#define TRANSLATE(ctype) \
    if (strcmp(encodingCString, @encode(ctype)) == 0) { \
        return (NSString *)CFSTR(#ctype); \
    }
    
    // Order matters here since some of the cocoa types are typedefed to c types.
    // We can't recover the exact mapping, but we choose to prefer the cocoa types.
    // This is not an exhaustive list, but it covers the most common types
    TRANSLATE(CGRect);
    TRANSLATE(CGPoint);
    TRANSLATE(CGSize);
    TRANSLATE(UIEdgeInsets);
    TRANSLATE(UIOffset);
    TRANSLATE(NSRange);
    TRANSLATE(CGAffineTransform);
    TRANSLATE(NSInteger);
    TRANSLATE(NSUInteger);
    TRANSLATE(CGFloat);
    TRANSLATE(BOOL);
    TRANSLATE(int);
    TRANSLATE(short);
    TRANSLATE(long);
    TRANSLATE(long long);
    TRANSLATE(unsigned char);
    TRANSLATE(unsigned int);
    TRANSLATE(unsigned short);
    TRANSLATE(unsigned long);
    TRANSLATE(unsigned long long);
    TRANSLATE(float);
    TRANSLATE(double);
    TRANSLATE(long double);
    TRANSLATE(char *);
    TRANSLATE(Class);
    TRANSLATE(objc_property_t);
    TRANSLATE(Ivar);
    TRANSLATE(Method);
    TRANSLATE(Category);
    TRANSLATE(NSZone *);
    TRANSLATE(SEL);
    TRANSLATE(void);
    
#undef TRANSLATE
    
    // Qualifier Prefixes
    // Do this after the checks above since some of the direct translations (i.e. Method) contain a prefix.
#define RECURSIVE_TRANSLATE(prefix, formatString) \
    if (encodingCString[0] == prefix) { \
        NSString *recursiveType = [self readableTypeForEncoding:[encodingString substringFromIndex:1]]; \
        return [NSString stringWithFormat:formatString, recursiveType]; \
    }
    
    // If there's a qualifier prefix on the encoding, translate it and then
    // recursively call this method with the rest of the encoding string.
    RECURSIVE_TRANSLATE('^', @"%@ *");
    RECURSIVE_TRANSLATE('r', @"const %@");
    RECURSIVE_TRANSLATE('n', @"in %@");
    RECURSIVE_TRANSLATE('N', @"inout %@");
    RECURSIVE_TRANSLATE('o', @"out %@");
    RECURSIVE_TRANSLATE('O', @"bycopy %@");
    RECURSIVE_TRANSLATE('R', @"byref %@");
    RECURSIVE_TRANSLATE('V', @"oneway %@");
    RECURSIVE_TRANSLATE('b', @"bitfield(%@)");
    
#undef RECURSIVE_TRANSLATE
    
    // If we couldn't translate, just return the original encoding string
    return encodingString;
}

+ (NSValue *)valueForPrimitivePointer:(void *)pointer objcType:(const char *)type
{
    // CASE marcro inspired by https://www.mikeash.com/pyblog/friday-qa-2013-02-08-lets-build-key-value-coding.html
#define CASE(ctype, selectorpart) \
    if(strcmp(type, @encode(ctype)) == 0) { \
        return [NSNumber numberWith ## selectorpart: *(ctype *)pointer]; \
    }
    
    CASE(BOOL, Bool);
    CASE(unsigned char, UnsignedChar);
    CASE(short, Short);
    CASE(unsigned short, UnsignedShort);
    CASE(int, Int);
    CASE(unsigned int, UnsignedInt);
    CASE(long, Long);
    CASE(unsigned long, UnsignedLong);
    CASE(long long, LongLong);
    CASE(unsigned long long, UnsignedLongLong);
    CASE(float, Float);
    CASE(double, Double);
    
#undef CASE
    
    NSValue *value = nil;
    @try {
        value = [NSValue valueWithBytes:pointer objCType:type];
    } @catch (NSException *exception) {
        // Certain type encodings are not supported by valueWithBytes:objCType:. Just fail silently if an exception is thrown.
    }
    
    return value;
}

+ (void)getPrimitiveValue:(void *)value withObjCType:(const char *)typeEncoding fromInputString:(NSString *)inputString
{
    if (strcmp(typeEncoding, @encode(CGRect)) == 0) {
        *(CGRect *)value = CGRectFromString(inputString);
    } else if (strcmp(typeEncoding, @encode(CGSize)) == 0) {
        *(CGSize *)value = CGSizeFromString(inputString);
    } else if (strcmp(typeEncoding, @encode(CGPoint)) == 0) {
        *(CGPoint *)value = CGPointFromString(inputString);
    } else if (strcmp(typeEncoding, @encode(CGAffineTransform)) == 0) {
        *(CGAffineTransform *)value = CGAffineTransformFromString(inputString);
    } else if (strcmp(typeEncoding, @encode(NSRange)) == 0) {
        *(NSRange *)value = NSRangeFromString(inputString);
    } else if (strcmp(typeEncoding, @encode(UIEdgeInsets)) == 0) {
        *(UIEdgeInsets *)value = UIEdgeInsetsFromString(inputString);
    } else if (strcmp(typeEncoding, @encode(UIOffset)) == 0) {
        *(UIOffset *)value = UIOffsetFromString(inputString);
    } else {
        NSNumberFormatter *formatter = [[NSNumberFormatter alloc] init];
        [formatter setNumberStyle:NSNumberFormatterDecimalStyle];
        NSNumber *number = [formatter numberFromString:inputString];
        
        if (strcmp(typeEncoding, @encode(char)) == 0) {
            // Special case - ask for the string's BOOL value if we couldn't parse a number.
            // This allows us to take YES/NO/true/false input.
            if (number) {
                *(char *)value = [number charValue];
            } else {
                *(char *)value = [inputString boolValue];
            }
        } else if (strcmp(typeEncoding, @encode(int)) == 0) {
            *(int *)value = [number intValue];
        } else if (strcmp(typeEncoding, @encode(short)) == 0) {
            *(short *)value = [number shortValue];
        } else if (strcmp(typeEncoding, @encode(long)) == 0) {
            *(long *)value = [number longValue];
        } else if (strcmp(typeEncoding, @encode(long long)) == 0) {
            *(long long *)value = [number longLongValue];
        } else if (strcmp(typeEncoding, @encode(unsigned char)) == 0) {
            *(unsigned char *)value = [number unsignedCharValue];
        } else if (strcmp(typeEncoding, @encode(unsigned int)) == 0) {
            *(unsigned int *)value = [number unsignedIntValue];
        } else if (strcmp(typeEncoding, @encode(unsigned short)) == 0) {
            *(unsigned short *)value = [number unsignedShortValue];
        } else if (strcmp(typeEncoding, @encode(unsigned long)) == 0) {
            *(unsigned long *)value = [number unsignedLongValue];
        } else if (strcmp(typeEncoding, @encode(unsigned long long)) == 0) {
            *(unsigned long long *)value = [number unsignedLongLongValue];
        } else if (strcmp(typeEncoding, @encode(float)) == 0) {
            *(float *)value = [number floatValue];
        } else if (strcmp(typeEncoding, @encode(double)) == 0) {
            *(double *)value = [number doubleValue];
        } else {
            // If we didn't match one of the supported types, fill the buffer with zeros.
            NSUInteger bytes = 0;
            NSGetSizeAndAlignment(typeEncoding, &bytes, NULL);
            memset(value, 0, bytes);
        }
    }
}

@end