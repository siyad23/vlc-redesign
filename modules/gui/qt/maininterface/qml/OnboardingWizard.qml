/*****************************************************************************
 * Copyright (C) 2026 VLC authors and VideoLAN
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * ( at your option ) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston MA 02110-1301, USA.
 *****************************************************************************/
import QtQuick
import QtQuick.Controls
import QtQuick.Templates as T
import QtQuick.Layouts

import VLC.MainInterface
import VLC.Widgets as Widgets
import VLC.Style
import VLC.Network
import VLC.Util

FocusScope {
    id: root

    focus: true

    property int currentStep: 0
    readonly property int totalSteps: 5

    property bool enableMetadataNetworkAccess: true
    property bool pinControls: MainCtx.pinVideoControls
    property string activeShortcutKey: ""

    readonly property var languagesModel: MainCtx.availableLanguages()

    readonly property var stepTitles: [
        qsTr("Welcome to VLC"),
        qsTr("Media Library Folders"),
        qsTr("Choose Your Theme"),
        qsTr("Accent Color & Controls"),
        qsTr("Playback Shortcuts")
    ]

    readonly property var stepSubtitles: [
        qsTr("Select your preferred language and metadata privacy preferences."),
        qsTr("Choose which folders VLC should scan for your videos and music."),
        qsTr("Pick a visual theme — including true #000000 AMOLED Black."),
        qsTr("Customize VLC's signature accent color and playback bar behavior."),
        qsTr("Press any key below to test VLC's core playback shortcuts.")
    ]

    readonly property var shortcutCards: [
        { key: "Space", matchKeys: [Qt.Key_Space], label: qsTr("Play / Pause"), desc: qsTr("Toggle playback instantly") },
        { key: "F", matchKeys: [Qt.Key_F], label: qsTr("Fullscreen"), desc: qsTr("Toggle fullscreen video") },
        { key: "M", matchKeys: [Qt.Key_M], label: qsTr("Mute"), desc: qsTr("Mute or unmute audio") },
        { key: "← / →", matchKeys: [Qt.Key_Left, Qt.Key_Right], label: qsTr("Seek ±10s"), desc: qsTr("Jump backward or forward") },
        { key: "↑ / ↓", matchKeys: [Qt.Key_Up, Qt.Key_Down], label: qsTr("Volume"), desc: qsTr("Adjust playback volume") },
        { key: "[ / ]", matchKeys: [Qt.Key_BracketLeft, Qt.Key_BracketRight], label: qsTr("Playback Speed"), desc: qsTr("Slow down or speed up") },
        { key: "V", matchKeys: [Qt.Key_V], label: qsTr("Cycle Subtitles"), desc: qsTr("Switch subtitle track") },
        { key: "B", matchKeys: [Qt.Key_B], label: qsTr("Cycle Audio"), desc: qsTr("Switch audio track") },
        { key: "E", matchKeys: [Qt.Key_E], label: qsTr("Next Frame"), desc: qsTr("Step forward frame-by-frame") }
    ]

    ColorContext {
        id: theme
        palette: VLCStyle.palette
        colorSet: ColorContext.Window
    }

    MLFolderModel {
        id: foldersModel
        ctx: MainCtx.mediaLibraryAvailable ? MainCtx : null
    }

    Timer {
        id: keyHighlightResetTimer
        interval: 650
        repeat: false
        onTriggered: root.activeShortcutKey = ""
    }

    Keys.priority: Keys.BeforeItem
    Keys.onPressed: (event) => {
        if (root.currentStep === 4) {
            for (let i = 0; i < root.shortcutCards.length; ++i) {
                const card = root.shortcutCards[i]
                if (card.matchKeys.indexOf(event.key) !== -1) {
                    root.activeShortcutKey = card.key
                    keyHighlightResetTimer.restart()
                    event.accepted = true
                    return
                }
            }
        }
        if (event.key === Qt.Key_Escape) {
            event.accepted = true
        }
    }

    // Full-window modal backdrop
    Widgets.ViewBlockingRectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.72)

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            onClicked: root.forceActiveFocus()
        }
    }

    // Centered Onboarding Card
    Rectangle {
        id: cardContainer

        anchors.centerIn: parent
        width: Math.min(parent.width - VLCStyle.margin_xlarge * 2, VLCStyle.dp(740, VLCStyle.scale))
        height: Math.min(parent.height - VLCStyle.margin_xlarge * 2, VLCStyle.dp(560, VLCStyle.scale))
        radius: VLCStyle.dp(16, VLCStyle.scale)
        color: theme.bg.primary
        border.width: VLCStyle.dp(1, VLCStyle.scale)
        border.color: theme.border

        Behavior on color {
            ColorAnimation { duration: VLCStyle.duration_short }
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: VLCStyle.margin_xlarge
            spacing: VLCStyle.margin_large

            // Top Header: Step indicator pills + Skip button
            RowLayout {
                Layout.fillWidth: true
                spacing: VLCStyle.margin_normal

                Row {
                    spacing: VLCStyle.margin_xsmall

                    Repeater {
                        model: root.totalSteps
                        delegate: Rectangle {
                            required property int index
                            width: (index === root.currentStep) ? VLCStyle.dp(28, VLCStyle.scale) : VLCStyle.dp(8, VLCStyle.scale)
                            height: VLCStyle.dp(8, VLCStyle.scale)
                            radius: VLCStyle.dp(4, VLCStyle.scale)
                            color: (index <= root.currentStep) ? theme.accent : theme.bg.secondary

                            Behavior on width {
                                NumberAnimation { duration: VLCStyle.duration_short; easing.type: Easing.OutCubic }
                            }
                            Behavior on color {
                                ColorAnimation { duration: VLCStyle.duration_short }
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.currentStep = index
                            }
                        }
                    }
                }

                Widgets.CaptionLabel {
                    text: qsTr("Step %1 of %2").arg(root.currentStep + 1).arg(root.totalSteps)
                    color: theme.fg.secondary
                    Layout.leftMargin: VLCStyle.margin_xsmall
                }

                Item { Layout.fillWidth: true }

                Widgets.ButtonExt {
                    text: qsTr("Skip Setup")
                    onClicked: {
                        MainCtx.completeFirstRun(root.enableMetadataNetworkAccess, root.pinControls)
                    }
                }
            }

            // Step Title & Subtitle
            ColumnLayout {
                Layout.fillWidth: true
                spacing: VLCStyle.margin_xxsmall

                Widgets.SubtitleLabel {
                    text: root.stepTitles[root.currentStep]
                    color: theme.fg.primary
                    font.pixelSize: VLCStyle.fontSize_xxlarge
                    font.weight: Font.Bold
                }

                Widgets.MenuCaption {
                    text: root.stepSubtitles[root.currentStep]
                    color: theme.fg.secondary
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                }
            }

            // Step Content Area
            StackLayout {
                id: stepStack
                Layout.fillWidth: true
                Layout.fillHeight: true
                currentIndex: root.currentStep

                // =========================================================
                // STEP 1: Welcome, Language & Metadata Privacy
                // =========================================================
                ColumnLayout {
                    spacing: VLCStyle.margin_large

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: VLCStyle.margin_large

                        Widgets.BannerCone {
                            color: theme.accent
                            Layout.preferredWidth: VLCStyle.dp(72, VLCStyle.scale)
                            Layout.preferredHeight: VLCStyle.dp(72, VLCStyle.scale)
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: VLCStyle.margin_xsmall

                            Widgets.MenuLabel {
                                text: qsTr("Application Language")
                                color: theme.fg.primary
                            }

                            ComboBox {
                                id: languageCombo
                                Layout.fillWidth: true
                                Layout.preferredHeight: VLCStyle.dp(38, VLCStyle.scale)
                                model: root.languagesModel
                                textRole: "label"
                                valueRole: "code"

                                Component.onCompleted: {
                                    const currentLang = MainCtx.appLanguage
                                    for (let i = 0; i < root.languagesModel.length; ++i) {
                                        if (root.languagesModel[i].code === currentLang) {
                                            currentIndex = i
                                            break
                                        }
                                    }
                                }

                                onActivated: (index) => {
                                    if (index >= 0 && index < root.languagesModel.length) {
                                        MainCtx.appLanguage = root.languagesModel[index].code
                                    }
                                }

                                contentItem: Text {
                                    leftPadding: VLCStyle.margin_normal
                                    rightPadding: languageCombo.indicator.width + VLCStyle.margin_normal
                                    text: languageCombo.displayText
                                    font.family: VLCStyle.fontFamily
                                    font.pixelSize: VLCStyle.fontSize_normal
                                    color: theme.fg.primary
                                    verticalAlignment: Text.AlignVCenter
                                    elide: Text.ElideRight
                                }

                                background: Rectangle {
                                    radius: VLCStyle.dp(8, VLCStyle.scale)
                                    color: theme.bg.secondary
                                    border.width: VLCStyle.dp(1, VLCStyle.scale)
                                    border.color: languageCombo.activeFocus ? theme.accent : theme.border
                                }
                            }
                        }
                    }

                    // Privacy & Metadata Consent Card
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        radius: VLCStyle.dp(12, VLCStyle.scale)
                        color: theme.bg.secondary
                        border.width: VLCStyle.dp(1, VLCStyle.scale)
                        border.color: theme.border

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: VLCStyle.margin_normal
                            spacing: VLCStyle.margin_small

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: VLCStyle.margin_normal

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: VLCStyle.margin_xxsmall

                                    Widgets.MenuLabel {
                                        text: qsTr("Allow Metadata & Cover Art Network Access")
                                        color: theme.fg.primary
                                    }

                                    Widgets.CaptionLabel {
                                        text: qsTr("VLC never collects or transmits personal telemetry. When enabled, VLC can fetch album art and track metadata from online services.")
                                        color: theme.fg.secondary
                                        wrapMode: Text.WordWrap
                                        Layout.fillWidth: true
                                    }
                                }

                                CheckBox {
                                    id: privacyCheck
                                    checked: root.enableMetadataNetworkAccess
                                    onToggled: root.enableMetadataNetworkAccess = checked
                                }
                            }
                        }
                    }
                }

                // =========================================================
                // STEP 2: Primary Media Folder Scan Locations
                // =========================================================
                ColumnLayout {
                    spacing: VLCStyle.margin_normal

                    RowLayout {
                        Layout.fillWidth: true

                        Widgets.MenuLabel {
                            text: qsTr("Watched Media Folders")
                            color: theme.fg.primary
                        }

                        Item { Layout.fillWidth: true }

                        Widgets.ButtonExt {
                            text: qsTr("Add Folder...")
                            iconTxt: VLCIcons.add
                            enabled: MainCtx.mediaLibraryAvailable
                            onClicked: {
                                const newUrl = MainCtx.chooseFolderDialog()
                                if (newUrl && newUrl.toString().length > 0) {
                                    foldersModel.add(newUrl)
                                }
                            }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        radius: VLCStyle.dp(12, VLCStyle.scale)
                        color: theme.bg.secondary
                        border.width: VLCStyle.dp(1, VLCStyle.scale)
                        border.color: theme.border
                        clip: true

                        ListView {
                            id: folderListView
                            anchors.fill: parent
                            anchors.margins: VLCStyle.margin_small
                            spacing: VLCStyle.margin_xsmall
                            model: foldersModel
                            visible: MainCtx.mediaLibraryAvailable && count > 0

                            delegate: Rectangle {
                                required property int index
                                required property string display_url

                                width: folderListView.width
                                height: VLCStyle.dp(42, VLCStyle.scale)
                                radius: VLCStyle.dp(8, VLCStyle.scale)
                                color: theme.bg.primary
                                border.width: VLCStyle.dp(1, VLCStyle.scale)
                                border.color: theme.border

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: VLCStyle.margin_normal
                                    anchors.rightMargin: VLCStyle.margin_small
                                    spacing: VLCStyle.margin_normal

                                    Widgets.ListLabel {
                                        text: display_url
                                        color: theme.fg.primary
                                        elide: Text.ElideMiddle
                                        Layout.fillWidth: true
                                    }

                                    Widgets.IconToolButton {
                                        text: VLCIcons.close
                                        description: qsTr("Remove folder")
                                        onClicked: foldersModel.removeAt(index)
                                    }
                                }
                            }
                        }

                        Widgets.CaptionLabel {
                            anchors.centerIn: parent
                            visible: !MainCtx.mediaLibraryAvailable || folderListView.count === 0
                            text: MainCtx.mediaLibraryAvailable
                                  ? qsTr("No media folders added yet. Click 'Add Folder...' to index your library.")
                                  : qsTr("Media Library indexing is disabled in current VLC configuration.")
                            color: theme.fg.secondary
                            horizontalAlignment: Text.AlignHCenter
                            width: parent.width - VLCStyle.margin_xlarge * 2
                            wrapMode: Text.WordWrap
                        }
                    }
                }

                // =========================================================
                // STEP 3: Theme Mode Selection (Dark, AMOLED, Light, System)
                // =========================================================
                GridLayout {
                    columns: 2
                    rowSpacing: VLCStyle.margin_normal
                    columnSpacing: VLCStyle.margin_normal

                    Repeater {
                        model: [
                            {
                                scheme: ColorSchemeModel.Night,
                                title: qsTr("Dark (Default)"),
                                subtitle: qsTr("Deep carbon surfaces designed for comfortable cinema viewing"),
                                previewBg: "#121212",
                                previewSurface: "#1E1E1E",
                                previewText: "#FFFFFF"
                            },
                            {
                                scheme: ColorSchemeModel.Amoled,
                                title: qsTr("AMOLED Black"),
                                subtitle: qsTr("Pure #000000 pitch-black canvas with subtle #0A0A0A elevated surfaces"),
                                previewBg: "#000000",
                                previewSurface: "#0A0A0A",
                                previewText: "#FFFFFF"
                            },
                            {
                                scheme: ColorSchemeModel.Day,
                                title: qsTr("Light"),
                                subtitle: qsTr("Crisp daylight surfaces with high-contrast typography"),
                                previewBg: "#FAFAFA",
                                previewSurface: "#EDEDED",
                                previewText: "#121212"
                            },
                            {
                                scheme: ColorSchemeModel.System,
                                title: qsTr("System Auto"),
                                subtitle: qsTr("Automatically follow your operating system's day/night schedule"),
                                previewBg: "#1E1E1E",
                                previewSurface: "#2D2D2D",
                                previewText: "#FFFFFF"
                            }
                        ]

                        delegate: Rectangle {
                            required property var modelData
                            required property int index

                            readonly property bool isSelected: MainCtx.colorScheme.scheme === modelData.scheme

                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            radius: VLCStyle.dp(12, VLCStyle.scale)
                            color: theme.bg.secondary
                            border.width: isSelected ? VLCStyle.dp(2, VLCStyle.scale) : VLCStyle.dp(1, VLCStyle.scale)
                            border.color: isSelected ? theme.accent : theme.border

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: VLCStyle.margin_normal
                                spacing: VLCStyle.margin_small

                                // Mini window preview
                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    radius: VLCStyle.dp(8, VLCStyle.scale)
                                    color: modelData.previewBg
                                    border.width: VLCStyle.dp(1, VLCStyle.scale)
                                    border.color: "#2E2E2E"

                                    Rectangle {
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.bottom: parent.bottom
                                        anchors.margins: VLCStyle.margin_small
                                        height: VLCStyle.dp(18, VLCStyle.scale)
                                        radius: VLCStyle.dp(6, VLCStyle.scale)
                                        color: modelData.previewSurface

                                        Rectangle {
                                            anchors.verticalCenter: parent.verticalCenter
                                            anchors.left: parent.left
                                            anchors.leftMargin: VLCStyle.margin_small
                                            width: parent.width * 0.45
                                            height: VLCStyle.dp(4, VLCStyle.scale)
                                            radius: VLCStyle.dp(2, VLCStyle.scale)
                                            color: theme.accent
                                        }
                                    }
                                }

                                Widgets.MenuLabel {
                                    text: modelData.title
                                    color: isSelected ? theme.accent : theme.fg.primary
                                }

                                Widgets.CaptionLabel {
                                    text: modelData.subtitle
                                    color: theme.fg.secondary
                                    Layout.fillWidth: true
                                    wrapMode: Text.WordWrap
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: MainCtx.colorScheme.setCurrentScheme(modelData.scheme)
                            }
                        }
                    }
                }

                // =========================================================
                // STEP 4: Custom Accent Color Palette & Control Bar Style
                // =========================================================
                ColumnLayout {
                    spacing: VLCStyle.margin_large

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: VLCStyle.margin_small

                        Widgets.MenuLabel {
                            text: qsTr("Accent Color Swatch")
                            color: theme.fg.primary
                        }

                        Flow {
                            Layout.fillWidth: true
                            spacing: VLCStyle.margin_small

                            Repeater {
                                model: VLCStyle.palette.accentSwatches

                                delegate: Rectangle {
                                    required property var modelData
                                    readonly property bool isCurrentSwatch: VLCStyle.palette.accentColor.toLowerCase() === modelData.id.toLowerCase()

                                    width: VLCStyle.dp(132, VLCStyle.scale)
                                    height: VLCStyle.dp(40, VLCStyle.scale)
                                    radius: VLCStyle.dp(20, VLCStyle.scale)
                                    color: theme.bg.secondary
                                    border.width: isCurrentSwatch ? VLCStyle.dp(2, VLCStyle.scale) : VLCStyle.dp(1, VLCStyle.scale)
                                    border.color: isCurrentSwatch ? theme.accent : theme.border

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: VLCStyle.margin_small
                                        anchors.rightMargin: VLCStyle.margin_small
                                        spacing: VLCStyle.margin_xsmall

                                        Rectangle {
                                            width: VLCStyle.dp(18, VLCStyle.scale)
                                            height: VLCStyle.dp(18, VLCStyle.scale)
                                            radius: VLCStyle.dp(9, VLCStyle.scale)
                                            color: modelData.color
                                        }

                                        Widgets.CaptionLabel {
                                            text: modelData.name
                                            color: theme.fg.primary
                                            elide: Text.ElideRight
                                            Layout.fillWidth: true
                                        }
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: VLCStyle.palette.accentColor = modelData.id
                                    }
                                }
                            }
                        }
                    }

                    // Floating Quiet Bars vs Pinned Classic Controls
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        spacing: VLCStyle.margin_small

                        Widgets.MenuLabel {
                            text: qsTr("Playback Control Bar Style")
                            color: theme.fg.primary
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            spacing: VLCStyle.margin_normal

                            // Option A: Floating Quiet Bars
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                radius: VLCStyle.dp(12, VLCStyle.scale)
                                color: theme.bg.secondary
                                border.width: !root.pinControls ? VLCStyle.dp(2, VLCStyle.scale) : VLCStyle.dp(1, VLCStyle.scale)
                                border.color: !root.pinControls ? theme.accent : theme.border

                                ColumnLayout {
                                    anchors.fill: parent
                                    anchors.margins: VLCStyle.margin_normal
                                    spacing: VLCStyle.margin_xsmall

                                    Widgets.MenuLabel {
                                        text: qsTr("Floating Quiet Bars (Recommended)")
                                        color: !root.pinControls ? theme.accent : theme.fg.primary
                                    }

                                    Widgets.CaptionLabel {
                                        text: qsTr("Edge-to-edge video with translucent floating controls that fade out smoothly when your cursor is idle.")
                                        color: theme.fg.secondary
                                        Layout.fillWidth: true
                                        wrapMode: Text.WordWrap
                                    }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.pinControls = false
                                }
                            }

                            // Option B: Pinned Controls
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                radius: VLCStyle.dp(12, VLCStyle.scale)
                                color: theme.bg.secondary
                                border.width: root.pinControls ? VLCStyle.dp(2, VLCStyle.scale) : VLCStyle.dp(1, VLCStyle.scale)
                                border.color: root.pinControls ? theme.accent : theme.border

                                ColumnLayout {
                                    anchors.fill: parent
                                    anchors.margins: VLCStyle.margin_normal
                                    spacing: VLCStyle.margin_xsmall

                                    Widgets.MenuLabel {
                                        text: qsTr("Pinned Bottom Controls")
                                        color: root.pinControls ? theme.accent : theme.fg.primary
                                    }

                                    Widgets.CaptionLabel {
                                        text: qsTr("Classic docked control bar permanently visible below the video viewport.")
                                        color: theme.fg.secondary
                                        Layout.fillWidth: true
                                        wrapMode: Text.WordWrap
                                    }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.pinControls = true
                                }
                            }
                        }
                    }
                }

                // =========================================================
                // STEP 5: Interactive Playback Shortcuts Cheat-Sheet
                // =========================================================
                GridLayout {
                    columns: 3
                    rowSpacing: VLCStyle.margin_small
                    columnSpacing: VLCStyle.margin_small

                    Repeater {
                        model: root.shortcutCards

                        delegate: Rectangle {
                            required property var modelData
                            readonly property bool isHighlighted: root.activeShortcutKey === modelData.key

                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            radius: VLCStyle.dp(10, VLCStyle.scale)
                            color: isHighlighted ? Qt.rgba(theme.accent.r, theme.accent.g, theme.accent.b, 0.18) : theme.bg.secondary
                            border.width: isHighlighted ? VLCStyle.dp(2, VLCStyle.scale) : VLCStyle.dp(1, VLCStyle.scale)
                            border.color: isHighlighted ? theme.accent : theme.border
                            scale: isHighlighted ? 1.03 : 1.0

                            Behavior on scale {
                                NumberAnimation { duration: VLCStyle.duration_short; easing.type: Easing.OutBack }
                            }
                            Behavior on color {
                                ColorAnimation { duration: VLCStyle.duration_short }
                            }

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: VLCStyle.margin_normal
                                spacing: VLCStyle.margin_xsmall

                                Rectangle {
                                    radius: VLCStyle.dp(6, VLCStyle.scale)
                                    color: isHighlighted ? theme.accent : theme.bg.primary
                                    border.width: VLCStyle.dp(1, VLCStyle.scale)
                                    border.color: isHighlighted ? theme.accent : theme.border
                                    implicitWidth: keyLabel.implicitWidth + VLCStyle.margin_normal * 2
                                    implicitHeight: VLCStyle.dp(28, VLCStyle.scale)

                                    Widgets.MenuLabel {
                                        id: keyLabel
                                        anchors.centerIn: parent
                                        text: modelData.key
                                        color: isHighlighted ? "#000000" : theme.accent
                                    }
                                }

                                Widgets.MenuLabel {
                                    text: modelData.label
                                    color: theme.fg.primary
                                }

                                Widgets.CaptionLabel {
                                    text: modelData.desc
                                    color: theme.fg.secondary
                                    Layout.fillWidth: true
                                    wrapMode: Text.WordWrap
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    root.activeShortcutKey = modelData.key
                                    keyHighlightResetTimer.restart()
                                    root.forceActiveFocus()
                                }
                            }
                        }
                    }
                }
            }

            // Bottom Navigation Bar: Back / Next / Get Started
            RowLayout {
                Layout.fillWidth: true
                spacing: VLCStyle.margin_normal

                Widgets.ButtonExt {
                    text: qsTr("Back")
                    visible: root.currentStep > 0
                    onClicked: {
                        if (root.currentStep > 0)
                            root.currentStep -= 1
                    }
                }

                Item { Layout.fillWidth: true }

                Widgets.ButtonExt {
                    text: (root.currentStep < root.totalSteps - 1) ? qsTr("Continue") : qsTr("Start Using VLC")
                    highlighted: true
                    onClicked: {
                        if (root.currentStep < root.totalSteps - 1) {
                            root.currentStep += 1
                            root.forceActiveFocus()
                        } else {
                            MainCtx.completeFirstRun(root.enableMetadataNetworkAccess, root.pinControls)
                        }
                    }
                }
            }
        }
    }
}
