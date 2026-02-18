//
//  MonkeycraftWidgetBundle.swift
//  MonkeycraftWidget
//
//  Created by weikeng on 2/18/26.
//

import WidgetKit
import SwiftUI

@main
struct MonkeycraftWidgetBundle: WidgetBundle {
    var body: some Widget {
        MonkeycraftWidget()
        MonkeycraftWidgetLiveActivity()
    }
}
