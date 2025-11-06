//
//  AproposMagazinev2Tests.swift
//  AproposMagazinev2Tests
//
//  Created by Auto on 27/10/2024.
//

import XCTest
@testable import AproposMagazinev2

final class AproposMagazinev2Tests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func testExample() throws {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct results.
        XCTAssertTrue(true, "Basic test should pass")
    }

    func testThemeManager() throws {
        // Test that ThemeManager singleton works
        let themeManager = ThemeManager.shared
        XCTAssertNotNil(themeManager, "ThemeManager should exist")
        
        // Test default theme
        XCTAssertEqual(themeManager.currentTheme, .system, "Default theme should be system")
        
        // Test theme switching
        themeManager.setTheme(.light)
        XCTAssertEqual(themeManager.currentTheme, .light, "Theme should be light")
        
        themeManager.setTheme(.dark)
        XCTAssertEqual(themeManager.currentTheme, .dark, "Theme should be dark")
        
        // Reset to system
        themeManager.setTheme(.system)
        XCTAssertEqual(themeManager.currentTheme, .system, "Theme should be system")
    }

    func testPerformanceExample() throws {
        // This is an example of a performance test case.
        self.measure {
            // Put the code you want to measure the time of here.
        }
    }
}
