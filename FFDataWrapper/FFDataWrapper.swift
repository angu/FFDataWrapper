//
//  FFDataWrapper.swift
//  FFDataWrapper
//
//  Created by Sergey Novitsky on 21/09/2017.
//  Copyright © 2017 Flock of Files. All rights reserved.
//

import Foundation

public typealias FFDataWrapperCoder = (UnsafeBufferPointer<UInt8>, UnsafeMutableBufferPointer<UInt8>) -> Void

/// FFDataWrapper is a struct which wraps a piece of data and provides some custom internal representation for it.
/// Conversions between original and internal representations can be specified with encoder and decoder closures.
public struct FFDataWrapper
{
    /// Class holding the data buffer and responsible for wiping the data when FFDataWrapper is destroyed.
    internal let dataRef: FFDataRef
    
    /// Closure to convert external representation to internal.
    internal let encoder: FFDataWrapperCoder
    
    /// Closure to convert internal representation to external.
    internal let decoder: FFDataWrapperCoder
    
    /// Initialize the data wrapper with the given string content and a pair of coder/decoder to convert between representations.
    ///
    /// - Parameters:
    ///   - string: The string data to wrap. The string gets converted to UTF8 data before being fed to the encoder closure.
    ///   - coders: The encoder/decoder pair which performs the conversion between external and internal representations.
    public init(_ string: String, _ coders: (encoder: FFDataWrapperCoder, decoder: FFDataWrapperCoder))
    {
        self.encoder = coders.encoder
        self.decoder = coders.decoder
        
        let utf8 = string.utf8CString
        let length = string.lengthOfBytes(using: .utf8) // utf8.count also accounts for the last 0 byte.

        let bufferPtr = UnsafeMutablePointer<UInt8>.allocate(capacity: length)
        dataRef = FFDataRef(dataBuffer: bufferPtr, length: length)
        
        // If length is 0 there may not be a pointer to the string content
        if (length > 0)
        {
            // Obfuscate the data
            utf8.withUnsafeBytes {
                coders.encoder(UnsafeBufferPointer(start: $0.baseAddress!.assumingMemoryBound(to: UInt8.self), count:length),
                               UnsafeMutableBufferPointer(start: self.dataRef.dataBuffer, count:length))
            }
        }
    }
    
    
    /// Create a wrapper with the given string content and use the XOR transformation for internal representation.
    /// (Good for simple obfuscation).
    /// - Parameter string: The string whose contents to wrap.
    public init(_ string: String)
    {
        self.init(string, FFDataWrapperEncoders.xorWithRandomVectorOfLength(string.utf8.count).coders)
    }
    
    
    /// Create a wrapper with the given data content and use the specified pair of coders to convert to/from the internal representation.
    ///
    /// - Parameters:
    ///   - data: The data to wrap.
    ///   - coders: Pair of coders to use to convert to/from the internal representation.
    public init(_ data: Data, _ coders: (encoder: FFDataWrapperCoder, decoder: FFDataWrapperCoder))
    {
        self.encoder = coders.encoder
        self.decoder = coders.decoder

        let length = data.count
        let bufferPtr = UnsafeMutablePointer<UInt8>.allocate(capacity: data.count == 0 ? 1 : data.count)
        dataRef = FFDataRef(dataBuffer: bufferPtr, length: length)
        
        if (length > 0)
        {
            // Encode the data
            data.withUnsafeBytes {
                coders.encoder(UnsafeBufferPointer(start: $0, count: length),
                               UnsafeMutableBufferPointer(start: self.dataRef.dataBuffer, count: length))
            }
        }
    }
    
    
    /// Create a wrapper with the given capacity and the given initializer closure.
    ///
    /// - Parameters:
    ///   - capacity: The desired capacity.
    ///   - initializer: Initializer closure to set initial contents.
    ///   - coders: Pair of coders to use to convert to/from the internal representation.
    public init(capacity: Int,
                _ initializer: (UnsafeMutableBufferPointer<UInt8>) -> Void,
                _ coders: (encoder: FFDataWrapperCoder, decoder: FFDataWrapperCoder))
    {
        self.encoder = coders.encoder
        self.decoder = coders.decoder
        let bufferPtr = UnsafeMutablePointer<UInt8>.allocate(capacity: capacity == 0 ? 1 : capacity)
        dataRef = FFDataRef(dataBuffer: bufferPtr, length: capacity)
        
        if (capacity > 0)
        {
            let tempBufferPtr = UnsafeMutablePointer<UInt8>.allocate(capacity: capacity)
            initializer(UnsafeMutableBufferPointer(start: tempBufferPtr, count: capacity))
            coders.encoder(UnsafeBufferPointer(start: tempBufferPtr, count: capacity),
                           UnsafeMutableBufferPointer(start: self.dataRef.dataBuffer, count: capacity))
            tempBufferPtr.initialize(to: 0, count: capacity)
            tempBufferPtr.deallocate(capacity: capacity)
        }
    }
    
    
    /// Create a wrapper with the given capacity and the given initializer closure.
    /// Use the XOR transformation for internal representation.
    /// - Parameters:
    ///   - capacity: The desired capacity.
    ///   - initializer: Initializer closure to set initial contents.
    public init(capacity: Int, _ initializer: (UnsafeMutableBufferPointer<UInt8>) -> Void)
    {
        self.init(capacity: capacity, initializer, FFDataWrapperEncoders.xorWithRandomVectorOfLength(capacity).coders)
    }
    
    /// Create a wrapper with the given data content and use the XOR transformation for internal representation.
    /// (Good for simple obfuscation).
    /// - Parameter data: The data whose contents to wrap.
    public init(_ data: Data)
    {
        let count = data.count
        self.init(data, FFDataWrapperEncoders.xorWithRandomVectorOfLength(count).coders)
    }
    
    
    /// Create a wrapper for an empty data value and use the specified pair of coders to convert to/from the internal representation.
    ///
    /// - Parameter coders: Pair of coders to use to convert to/from the internal representation.
    public init(_ coders: (encoder: FFDataWrapperCoder, decoder: FFDataWrapperCoder))
    {
        self.encoder = coders.encoder
        self.decoder = coders.decoder
        let bufferPtr = UnsafeMutablePointer<UInt8>.allocate(capacity: 1)
        dataRef = FFDataRef(dataBuffer: bufferPtr, length: 0)
    }
    
    /// Create a wrapper for an empty value and use the XOR transformation for internal representation (not really applied, just for consistency reasons).
    public init()
    {
        self.init(FFDataWrapperEncoders.xorWithRandomVectorOfLength(1).coders)
    }

    
    /// Execute the given closure with wrapped data.
    /// Data is converted back from its internal representation and is wiped after the closure is completed.
    /// Wiping of the data will succeed ONLY if the data is not passed outside the closure (i.e. if there are no additional references to it
    /// by the time the closure completes).
    /// - Parameter block: The closure to execute.
    @discardableResult
    public func withDecodedData<ResultType>(_ block: (inout Data) throws -> ResultType) rethrows -> ResultType
    {
        let dataLength = dataRef.length
        var decodedData = Data(repeating:0, count: dataLength)

        decodedData.withUnsafeMutableBytes({ (destPtr: UnsafeMutablePointer<UInt8>) -> Void in
            decoder(UnsafeBufferPointer(start: dataRef.dataBuffer, count: dataLength), UnsafeMutableBufferPointer(start: destPtr, count: dataLength))
        })
        
        let result = try block(&decodedData)
        
        decodedData.resetBytes(in: 0 ..< decodedData.count)
        
        return result
    }
    
    
    /// Returns true if the wrapped data is empty; false otherwise.
    public var isEmpty: Bool
    {
        return dataRef.length == 0
    }
    
    /// Returns the length of the underlying data
    public var length: Int
    {
        return dataRef.length
    }
}

extension FFDataWrapper: CustomStringConvertible
{
    public static func hexString(_ data: Data) -> String
    {
        var result = String()
        result.reserveCapacity(data.count * 2)
        for i in 0 ..< data.count
        {
            result += String(format: "%02X", data[i])
        }
        return result
    }

    func underlyingDataString() -> String
    {
        return self.withDecodedData { decodedData -> String in
            if let dataAsString = String(data: decodedData, encoding: .utf8)
            {
                return dataAsString
            }
            return FFDataWrapper.hexString(decodedData)
        }
    }
    
    public var description: String {
        return "FFDataWrapper: \(underlyingDataString())"
    }
}

extension FFDataWrapper: CustomDebugStringConvertible
{
    public var debugDescription: String {
        var result = "FFDataWrapper:\n"
        result += "Underlying data: \"\(underlyingDataString())\"\n"
        result += "dataRef: \(String(reflecting:dataRef))\n"
        result += "encoder: \(String(reflecting:encoder))\n"
        result += "decoder: \(String(reflecting:decoder))"
        return result
    }
}

extension FFDataWrapper: CustomPlaygroundQuickLookable
{
    public var customPlaygroundQuickLook: PlaygroundQuickLook
    {
        return .text(self.description)
    }
}



