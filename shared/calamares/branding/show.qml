import QtQuick 2.0
import calamares.slideshow 1.0

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
    Slide {
        Image {
            source: "toto-welcome.png"
            width: Math.min(parent.width * 0.35, 180)
            height: width
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: 24
            fillMode: Image.PreserveAspectFit
        }
        Text {
            anchors.centerIn: parent
            anchors.verticalCenterOffset: 80
            width: parent.width * 0.85
            text: qsTr("Your Total.js workspace") + "\n\n" + qsTr("Build with Node.js and Total.js. Open Code, connect your services and bring your projects to life.")
            textFormat: Text.PlainText
            wrapMode: Text.WordWrap
            horizontalAlignment: Text.AlignHCenter
            color: "#20252b"
            font.pixelSize: 19
        }
    }
    Slide {
        Text {
            anchors.centerIn: parent
            width: parent.width * 0.85
            text: qsTr("One familiar experience") + "\n\n" + qsTr("Ubuntu or Arch. Desktop or Server. The same Total.js tools, with packages managed by your system.")
            textFormat: Text.PlainText
            wrapMode: Text.WordWrap
            horizontalAlignment: Text.AlignHCenter
            color: "#20252b"
            font.pixelSize: 21
        }
    }
    Text {
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottomMargin: 12
        text: qsTr("Toto, mascot of Spanish Total.js · totaljs.es")
        color: "#626b60"
        font.pixelSize: 12
    }
}
