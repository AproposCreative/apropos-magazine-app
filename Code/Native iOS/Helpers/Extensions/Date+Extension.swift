//
//  Date+Extension.swift
//  Native
//

import Foundation

extension Date {
    
    // MARK: - Computed properties:
    
    /// 'Bool' value indicating whether or not the given date is today:
    var isToday: Bool {
        Calendar.current.isDateInToday(self)
    }
    
    /// 'Bool' value indicating whether or not the given date is in this month:
    var isThisMonth: Bool {
        
        /// Firstly getting the calendar to handle the dates:
        let calendar: Calendar = .current
        
        /// Then getting the date components for the given date:
        let dateComponents: DateComponents = calendar.dateComponents(
            [
                .year,
                .month
            ],
            from: self
        )
        
        /// Then getting an actual date for the given date that is based on the given date components:
        let date: Date = calendar.date(from: dateComponents) ?? .now
        
        /// Then getting the date components for the current date:
        let currentDateComponents: DateComponents = calendar.dateComponents(
            [
                .year,
                .month
            ],
            from: .now
        )
        
        /// Then getting an actual date for the current date that is based on the given current date components:
        let currentDate: Date = calendar.date(from: currentDateComponents) ?? .now
        
        /// Then getting a 'Bool' value indicating whether or not the given date is in this month that is based on the current date:
        let isThisMonth: Bool = date == currentDate
        
        /// Finally returning a 'Bool' value indicating whether or not the given date is in this month:
        return isThisMonth
    }
    
    /// Date for the start of the month that is based on the given date:
    var startOfMonth: Date {
        
        /// Firstly getting the calendar to handle the dates:
        let calendar: Calendar = .current
        
        /// Then getting the date components for the start of the month that are based on the given date:
        let dateComponents: DateComponents = calendar.dateComponents(
            [
                .year,
                .month
            ],
            from: self
        )
        
        /// Then getting an actual date for the start of the month that is based on the given date components:
        let startOfMonth: Date = calendar.date(from: dateComponents) ?? .now
        
        /// Lastly returning the date for the start of the month:
        return startOfMonth
    }
    
    // MARK: - Functions:
    
    /// Returns the date based on the given date components:
    static func dateWithComponents(
        withYear year: Int? = nil,
        withMonth month: Int? = nil,
        withDay day: Int? = nil,
        withHour hour: Int? = nil,
        withMinute minute: Int? = nil
    ) -> Self {
        
        /// Firstly getting the date components based on the values provided:
        let dateComponents: DateComponents = DateComponents(
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute
        )
        
        /// Then creating the date in the current calendar based on the given date components:
        let date: Date = Calendar.current.date(from: dateComponents) ?? .now
        
        /// Finally returning the date:
        return date
    }
}
