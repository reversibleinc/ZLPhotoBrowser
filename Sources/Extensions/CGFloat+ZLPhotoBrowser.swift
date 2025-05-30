//
//  CGFloat+ZLPhotoBrowser.swift
//  ZLPhotoBrowser
//
//  Created by long on 2020/11/10.
//
//  Copyright (c) 2020 Long Zhang <495181165@qq.com>
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.

import UIKit

extension CGFloat {
    
    var toPi: CGFloat {
        return self / 180 * .pi
    }
    
    var toInt: Int { return Int(self) }
    
    func durationString() -> String {
        
        let day: Int = self.toInt / (60 * 60 * 24)
        let hour: Int = (self.toInt - day * (60 * 60 * 24)) / (60 * 60)
        let minute: Int = (self.toInt - day * (60 * 60 * 24) - hour * (60 * 60)) / 60
        let second: Int = self.toInt - day * (60 * 60 * 24) - hour * (60 * 60) - minute * 60
        var timeString = ""
        if day >= 1 {
            timeString += "\(day) day "
        }
        if hour >= 1 {
            timeString += "\(hour.twoDigitString)"
        }
        
        if minute >= 0 {
            if hour >= 1 {
                timeString += ":"
            }
            timeString += "\(minute.twoDigitString)"
        }
        
        if second >= 1 {
            timeString += ":\(second.twoDigitString)"
        }
        return timeString
    }
    
}
