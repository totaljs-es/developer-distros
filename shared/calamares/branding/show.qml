import QtQuick 2.0
import calamares.slideshow 1.0

/* Total.js Developer slideshow: light canvas, dark text, Total.js green.
   Every string is an English key for qsTr(). Keep the palette in step with
   branding.desc and stylesheet.qss. */
Presentation {
    id: presentation
    function onActivate() { presentation.currentSlide = 0; }
    function onLeave() {}
    Timer {
        interval: 9000
        running: presentation.activatedInCalamares
        repeat: true
        onTriggered: presentation.goToNextSlide()
    }

    // The same canvas under every slide.
    Component {
        id: canvas
        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                GradientStop { position: 0.0; color: "#ffffff" }
                GradientStop { position: 1.0; color: "#eaf3e4" }
            }
            Rectangle { // the green band of the brand along the top edge
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                height: 6
                color: "#6ac043"
            }
        }
    }

    // Slide 1: welcome, with the penguin that hugs the Total.js logo.
    Slide {
        // fill the whole frame (the default Slide keeps margins of 5 % and 20 %)
        x: 0; y: 0; width: parent.width; height: parent.height
        Loader { anchors.fill: parent; sourceComponent: canvas }
        Image {
            id: hero
            source: "totalvm.png"
            fillMode: Image.PreserveAspectFit
            smooth: true
            height: Math.min(parent.height * 0.78, parent.width * 0.42)
            width: height
            anchors.right: parent.right
            anchors.rightMargin: parent.width * 0.05
            anchors.verticalCenter: parent.verticalCenter
        }
        Column {
            anchors.left: parent.left
            anchors.leftMargin: parent.width * 0.07
            anchors.right: hero.left
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            spacing: 14
            Rectangle { width: 54; height: 5; radius: 2; color: "#6ac043" }
            Text {
                width: parent.width
                text: qsTr("Your Total.js workspace")
                textFormat: Text.PlainText
                wrapMode: Text.WordWrap
                color: "#20252b"
                font.pixelSize: 34
                font.bold: true
            }
            Text {
                width: parent.width
                text: qsTr("Node.js, Total.js, Docker and PostgreSQL, installed and ready. Open your editor and start building.")
                textFormat: Text.PlainText
                wrapMode: Text.WordWrap
                color: "#3b444d"
                font.pixelSize: 18
                lineHeight: 1.15
            }
        }
    }

    // Slide 2: what is inside.
    Slide {
        // fill the whole frame (the default Slide keeps margins of 5 % and 20 %)
        x: 0; y: 0; width: parent.width; height: parent.height
        Loader { anchors.fill: parent; sourceComponent: canvas }
        Column {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: parent.width * 0.07
            anchors.verticalCenter: parent.verticalCenter
            spacing: 18
            Rectangle { width: 54; height: 5; radius: 2; color: "#6ac043" }
            Text {
                width: parent.width
                text: qsTr("Everything for Total.js")
                textFormat: Text.PlainText
                wrapMode: Text.WordWrap
                color: "#20252b"
                font.pixelSize: 32
                font.bold: true
            }
            Text {
                width: parent.width
                text: qsTr("The tools you reach for every day, in place from the first start.")
                textFormat: Text.PlainText
                wrapMode: Text.WordWrap
                color: "#3b444d"
                font.pixelSize: 18
            }
            Flow {
                width: parent.width
                spacing: 10
                Repeater {
                    model: [qsTr("Node.js"), qsTr("Total.js 4 and 5"), qsTr("Flow"), qsTr("Center"),
                            qsTr("Docker"), qsTr("PostgreSQL"), qsTr("Local HTTPS"), qsTr("totaljs.developer")]
                    Rectangle {
                        width: label.implicitWidth + 28
                        height: 38
                        radius: 19
                        color: "#ffffff"
                        border.color: "#6ac043"
                        border.width: 2
                        Text {
                            id: label
                            anchors.centerIn: parent
                            text: modelData
                            textFormat: Text.PlainText
                            color: "#20252b"
                            font.pixelSize: 16
                        }
                    }
                }
            }
        }
    }

    // Slide 3: one experience, four ways to install it.
    Slide {
        // fill the whole frame (the default Slide keeps margins of 5 % and 20 %)
        x: 0; y: 0; width: parent.width; height: parent.height
        Loader { anchors.fill: parent; sourceComponent: canvas }
        Column {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: parent.width * 0.07
            anchors.verticalCenter: parent.verticalCenter
            spacing: 18
            Rectangle { width: 54; height: 5; radius: 2; color: "#6ac043" }
            Text {
                width: parent.width
                text: qsTr("One familiar experience")
                textFormat: Text.PlainText
                wrapMode: Text.WordWrap
                color: "#20252b"
                font.pixelSize: 32
                font.bold: true
            }
            Text {
                width: parent.width
                text: qsTr("Ubuntu or Arch. Desktop or Server. The same Total.js tools, with packages managed by your system.")
                textFormat: Text.PlainText
                wrapMode: Text.WordWrap
                color: "#3b444d"
                font.pixelSize: 18
            }
            Row {
                spacing: 14
                Repeater {
                    model: [qsTr("Ubuntu"), qsTr("Arch"), qsTr("Desktop"), qsTr("Server")]
                    Rectangle {
                        width: Math.max(96, label3.implicitWidth + 36)
                        height: 56
                        radius: 8
                        color: index < 2 ? "#20252b" : "#6ac043"
                        Text {
                            id: label3
                            anchors.centerIn: parent
                            text: modelData
                            textFormat: Text.PlainText
                            color: index < 2 ? "#e5e9ee" : "#172019"
                            font.pixelSize: 19
                            font.bold: true
                        }
                    }
                }
            }
        }
    }

    // Slide 4: made for developers.
    Slide {
        // fill the whole frame (the default Slide keeps margins of 5 % and 20 %)
        x: 0; y: 0; width: parent.width; height: parent.height
        Loader { anchors.fill: parent; sourceComponent: canvas }
        Image {
            id: hero4
            source: "totalvm.png"
            fillMode: Image.PreserveAspectFit
            smooth: true
            height: Math.min(parent.height * 0.5, parent.width * 0.26)
            width: height
            anchors.left: parent.left
            anchors.leftMargin: parent.width * 0.06
            anchors.verticalCenter: parent.verticalCenter
        }
        Column {
            anchors.left: hero4.right
            anchors.leftMargin: parent.width * 0.04
            anchors.right: parent.right
            anchors.rightMargin: parent.width * 0.07
            anchors.verticalCenter: parent.verticalCenter
            spacing: 14
            Rectangle { width: 54; height: 5; radius: 2; color: "#6ac043" }
            Text {
                width: parent.width
                text: qsTr("Made for developers")
                textFormat: Text.PlainText
                wrapMode: Text.WordWrap
                color: "#20252b"
                font.pixelSize: 30
                font.bold: true
            }
            Text {
                width: parent.width
                text: qsTr("A light desktop that stays out of the way, a console always at hand, and signed packages that update like any other on your system.")
                textFormat: Text.PlainText
                wrapMode: Text.WordWrap
                color: "#3b444d"
                font.pixelSize: 18
                lineHeight: 1.15
            }
        }
    }
}
