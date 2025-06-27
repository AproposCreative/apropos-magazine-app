//
//  Formatters.swift
//  Native
//

import Foundation

struct Formatters {
    
    // MARK: - Properties:
    
    /// Formatter for the dates:
    static let dateFormatter: DateFormatter = {
        
        /// Firstly creating the date formatter:
        let formatter: DateFormatter = DateFormatter()
        
        /// Then setting the style of the date that will be returned by the date formatter:
        formatter.dateStyle = .medium
        
        /// Then setting the style of the time that will be returned by the date formatter:
        formatter.timeStyle = .short
        
        /// Lastly setting the 'doesRelativeDateFormatting' property of the date formatter to 'true' to also handle the relative dates, such as 'Yesterday', 'Today', etc.
        formatter.doesRelativeDateFormatting = true
        
        /// Finally returning the date formatter:
        return formatter
    }()
    
    /// Formatter for the date components:
    static let dateComponentsFormatter: DateComponentsFormatter = {
        
        /// Firstly creating the formatter for the date components:
        let formatter: DateComponentsFormatter = DateComponentsFormatter()
        
        /// Then setting an array of the units that can be used for the date that will be returned by the date components formatter:
        formatter.allowedUnits = [
            .hour,
            .minute,
            .second
        ]
        
        /// Lastly setting the unit style to be a full one to display the name of the actual unit (For example, 'minutes', etc.):
        formatter.unitsStyle = .full
        
        /// Finally returning the formatter for the date components:
        return formatter
    }()
    
    // MARK: - Functions:
    
    /// Returns the time interval between the given date and the other date provided as a string:
    static func timeInterval(
        fromDate: Date,
        toDate: Date = .now
    ) -> String? {
        
        /// Firstly creating the formatter for the date components:
        let formatter: DateComponentsFormatter = DateComponentsFormatter()
        
        /// Then setting the unit style to be a full one to display the name of the actual unit (For example, 'minutes', etc.):
        formatter.unitsStyle = .full
        
        /// Then getting the date components from the given date until the other date provided:
        let components: DateComponents = Calendar.current.dateComponents(
            [
                .year,
                .month,
                .day,
                .hour,
                .minute,
                .second
            ],
            from: fromDate,
            to: toDate
        )
        
        /// Then checking what the date component that we have:
        if let year: Int = components.year,
           year > 0 {
            
            /// If we have the year component, then setting the year unit as the only unit that is allowed to be displayed because if we set all of the units at once, then it will display all of them including minutes and seconds:
            formatter.allowedUnits = [.year]
        } else if let month: Int = components.month,
                  month > 0 {
            
            /// If we have the month component, then setting the month unit as the only unit that is allowed to be displayed because if we set all of the units at once, then it will display all of them including minutes and seconds:
            formatter.allowedUnits = [.month]
        } else if let day: Int = components.day,
                  day > 0 {
            
            /// If we have the day component, then setting the day unit as the only unit that is allowed to be displayed because if we set all of the units at once, then it will display all of them including minutes and seconds:
            formatter.allowedUnits = [.day]
        } else if let hour: Int = components.hour,
                  hour > 0 {
            
            /// If we have the hour component, then setting the hour unit as the only unit that is allowed to be displayed because if we set all of the units at once, then it will display all of them including minutes and seconds:
            formatter.allowedUnits = [.hour]
        } else if let minute: Int = components.minute,
                  minute > 0 {
            
            /// If we have the minute component, then setting the minute unit as the only unit that is allowed to be displayed because if we set all of the units at once, then it will display all of them including minutes and seconds:
            formatter.allowedUnits = [.minute]
        } else {
            
            /// If none of the above, then simply setting the second unit as the only unit that is allowed to be displayed because there are no other date components available:
            formatter.allowedUnits = [.second]
        }
        
        /// Lastly getting the time interval as a string using the given formatter for the date components:
        let timeInterval: String? = formatter.string(
            from: fromDate,
            to: toDate
        )
        
        /// Finally returning the time interval as a string:
        return timeInterval
    }
}
