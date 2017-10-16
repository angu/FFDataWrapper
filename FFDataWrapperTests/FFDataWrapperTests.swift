//
//  FFDataWrapperTests.swift
//  FFDataWrapperTests
//
//  Created by Sergey Novitsky on 21/09/2017.
//  Copyright © 2017 Flock of Files. All rights reserved.
//

import XCTest
@testable import FFDataWrapper

extension Data
{
    /// Convert data to a hex string
    ///
    /// - Returns: hex string representation of the data.
    func hexString() -> String
    {
        var result = String()
        result.reserveCapacity(self.count * 2)
        [UInt8](self).forEach { (aByte) in
            result += String(format: "%02X", aByte)
        }
        return result
    }
    
}

class FFDataWrapperTests: XCTestCase
{
    
    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }
    
    let testString = "ABCDEFGH"
    let shortTestString = "A"
    let utf16TestString = "AB❤️💛❌✅"
    let wipeCharacter = UInt8(46)

    func testUnsafeWipeUtf8String()
    {
        let expectedWipedString = String(testString.map { _ in Character(UnicodeScalar(wipeCharacter)) })
        var testUtf8String = String()
        testUtf8String.append(testString)
        
        FFDataWrapper.unsafeWipe(&testUtf8String, with: wipeCharacter)
        
        XCTAssertEqual(testUtf8String, expectedWipedString)
    }
    
    func testUnsafeWipeShortUtf8String()
    {
        let expectedWipedString = String(shortTestString.map { _ in Character(UnicodeScalar(wipeCharacter)) })
        var testUtf8String = String()
        testUtf8String.append(shortTestString)
        
        FFDataWrapper.unsafeWipe(&testUtf8String, with: wipeCharacter)
        
        XCTAssertEqual(testUtf8String, expectedWipedString)
    }
    
    func testUnsafeWipeUtf16String()
    {
        var testUtf16String = String()
        testUtf16String.append(utf16TestString)
        
        FFDataWrapper.unsafeWipe(&testUtf16String, with: wipeCharacter)
        
        let elements = Array(testUtf16String.utf16)
        elements.forEach {
            XCTAssertEqual($0, UInt16(wipeCharacter) * 256 + UInt16(wipeCharacter))
        }
    }
    
    func testWrapStringWithXOR()
    {
        let wrapper1 = FFDataWrapper(testString)
        
        var recoveredString = ""
        wrapper1.withDecodedData {
            recoveredString = String(data: $0, encoding: .utf8)!
            XCTAssertEqual(recoveredString, testString)
        }
        
        print(wrapper1.dataRef.dataBuffer)
        let testData = testString.data(using: .utf8)!
        let underlyingData = Data(bytes: wrapper1.dataRef.dataBuffer, count: wrapper1.dataRef.length)
        XCTAssertNotEqual(underlyingData, testData)

        
        let wrapper2 = wrapper1
        wrapper2.withDecodedData { data in
            recoveredString = String(data: data, encoding: .utf8)!
            XCTAssertEqual(recoveredString, testString)
        }
        
    }
    
    func testWraperStringWithCopy()
    {
        let wrapper1 = FFDataWrapper(testString, FFDataWrapperEncoders.identity.coders)
        
        var recoveredString = ""
        wrapper1.withDecodedData {
            recoveredString = String(data: $0, encoding: .utf8)!
            XCTAssertEqual(recoveredString, testString)
        }
        
        let testData = testString.data(using: .utf8)!
        let underlyingData = Data(bytes: wrapper1.dataRef.dataBuffer, count: wrapper1.dataRef.length)
        XCTAssertEqual(underlyingData, testData)
        
        let wrapper2 = wrapper1
        wrapper2.withDecodedData {
            recoveredString = String(data: $0, encoding: .utf8)!
            XCTAssertEqual(recoveredString, testString)
        }
    }
    
    func testWraperDataWithXOR()
    {
        let testData = testString.data(using: .utf8)!
        
        let wrapper1 = FFDataWrapper(testData)
        
        var recoveredString = ""
        wrapper1.withDecodedData {
            recoveredString = String(data: $0, encoding: .utf8)!
            XCTAssertEqual(recoveredString, testString)
        }

        let underlyingData = Data(bytes: wrapper1.dataRef.dataBuffer, count: wrapper1.dataRef.length)
        XCTAssertNotEqual(underlyingData, testData)

        let wrapper2 = wrapper1
        wrapper2.withDecodedData {
            recoveredString = String(data: $0, encoding: .utf8)!
            XCTAssertEqual(recoveredString, testString)
        }
    }
    
    fileprivate struct FFTestData
    {
        var backing : FFTestDataStorage
    }
    
    fileprivate class FFTestDataStorage
    {
        var bytes: UnsafeMutableRawPointer? = nil
        var length: Int = 0
    }
    
    /// Here we test that the temporary data which is given to the closure gets really wiped.
    /// This is the case where the data is NOT copied out.
    func testWipeAfterDecode()
    {
        let testString = "ABCDEF"
        let testData = testString.data(using: .utf8)!
        let testDataLength = testData.count
        
        let dataWrapper = FFDataWrapper(testData)
        var copiedBacking = Data()
        
        guard let bytes: UnsafeMutableRawPointer = dataWrapper.withDecodedData({ (data: inout Data) -> UnsafeMutableRawPointer? in
            let backing = { (_ o: UnsafeRawPointer) -> UnsafeRawPointer in o }(&data).assumingMemoryBound(to: FFTestData.self).pointee.backing
            if let bytes = backing.bytes
            {
                copiedBacking = Data(bytes: bytes, count: data.count)
            }
            return backing.bytes
        }) else {
            XCTFail("Expecting to have a data storage")
            return
        }
        
        let copiedBackingString = String(data: copiedBacking, encoding: .utf8)
        XCTAssertEqual(copiedBackingString, testString)
        let reconstructedBacking = Data(bytes: bytes, count: testDataLength)
        
        let expectedReconstructedBacking = Data.init(count: testDataLength)
        XCTAssertEqual(reconstructedBacking, expectedReconstructedBacking)
    }
    
    
    
}
