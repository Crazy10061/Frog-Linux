import QtQuick 2.0
import calamares.slideshow 1.0

Presentation {
    id: presentation

    Timer {
        interval: 5000
        running: presentation.activatedInCalamares
        repeat: true
        onTriggered: presentation.goToNextSlide()
    }

    Slide {
        Text {
            anchors.centerIn: parent
            text: "Welcome to Frog Linux"
            font.pixelSize: 32
            wrapMode: Text.WordWrap
        }
    }

    Slide {
        Text {
            anchors.centerIn: parent
            text: "Powered by Arch + CachyOS kernel"
            font.pixelSize: 28
            wrapMode: Text.WordWrap
        }
    }

    Slide {
        Text {
            anchors.centerIn: parent
            text: "Enjoy your install!"
            font.pixelSize: 28
            wrapMode: Text.WordWrap
        }
    }
}
