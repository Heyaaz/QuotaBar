import AppKit

@MainActor
enum ProviderIcons {
    // Embedded 32 px masks avoid runtime downloads and follow the current menu bar appearance.
    static func image(for provider: ProviderID) -> NSImage {
        switch provider {
        case .claude: claude
        case .codex: codex
        case .grok: grok
        }
    }

    private static let claude = tintedMask(
        """
        iVBORw0KGgoAAAANSUhEUgAAACAAAAAgCAYAAABzenr0AAAAAXNSR0IArs4c6QAAADhlWElmTU0AKgAAAAgAAYdpAAQAAAAB
        AAAAGgAAAAAAAqACAAQAAAABAAAAIKADAAQAAAABAAAAIAAAAACPTkDJAAAEzUlEQVRYCaWWaYhWVRjH1XHLMc0ZlVFMRx3B
        JRUUg8QytFKDRFFnNEcE0RjQrA/qB4soMmyhksiQrC+h6AejES1b0EYFC0wdBXEbzFzAXUvHrdJ+v3fusesd7zuv+sBvznrP
        ec7z/M95J69RdmvH8AcwDwphD/wNSWtJxyhoDmeSgw/SnsHHZ8FNL8AwyIOkVdBxGn6AjsnBbO0m2QYZawH50BQegXLwlHFz
        zljoAD2hFeRsDTmwnZU82a1oxdGUJVE9FG2pFEUN514OA1H5MOVk0MmHor6cC0/3HlwHnfgX1ENjCFZMpQYc/xr8JphRWwqn
        YB+Mh6xWwKgnim/QlbaRcHM3qYbOEOwxKm7g2JLQSdkaPgYj4tglWAx3WDwFAxj5Ar6BMgjhOk59GVwFrR9MyNTq/pjzNuAm
        RkJTJ7NhJuSDdg12ZGopf1T8GfCkF0BvFZZmZL6Df8CNDkCIwoio7yLlSFCwOhi04/wr4OF0NNUGMeI9D6HW47XQF4zUKAiL
        Oudt0KaAmxyGIhgCh8A+0ekN0AWymvd7OPwIQXTe/90wDnxslsMNcGE3UR9zo/Zmyk5QBTfBOZY1MBjiuqJZZ24azA/M9yaw
        bq7Nr2l4FlT3engafCHFiBTCk+B3/WEyGDHtT5gPG0FncjI9VTjjYTvEU1JJuwp0UKphdVT/nTIo3jGj+AkkHy66crNmTCuG
        d+E8uKgpEetifhWudU8Y76+iHURMNZMCr7jp8JbNgl7QoBkRBfgbhGiEjdJKIzENFJ6RfB/U1gHwzTA64WZkJulVH3gU2oNv
        QFI09vuweEXTNg79tczZC5dS5urgL1DuJqvAExpOHxs9sxSvoosoNgUqE2AMJB2k667mrVGMOqSm1M1BOAqnfTR8vz1dR2gB
        nt5cqQEF5E1xs3C60KbrruY8Hd0NW6AK3FTt1LNwChf1ygUH3Ny6DlgXF7ZvNkyCNHPeEfDEijdcP8uLUZ/C3QVGJGfrwUw1
        4D8obmLKLJPU0rcZ9oPpTI7bVsxHYFr8IaJdz4xAd6iApTACFNCvoMKNYBOIm32ebBasAVNxAtSBEXRPnTCqqfurjQ5guPeB
        p1WQP8F0+Bns2wZeqWQ0FN730BN0UKfaQW8YC2/Ba1AC9Uwvn4H14MKKxxO8CZ3hSzCfW+F1cLNNcA48mREy/94iHRwAqSdl
        7A4rpLUQ3NA8uci38BTo2ByohZMwBN4BNy2FT0HH/gKf4NWgBnRmOBjVBu0NZvjQGNY/wDAVgGF8DnTMVJgabS3owEjoBn6j
        EwrQKH4EwYkXqDeDrDaVUU/8GQyFILC+1PeA6VgGRqM1eL916AnQXoaQNgWo8wvgLByGUsjqhGFqk5hURLsSzLXqV1haP/CF
        PBXVKTI/zRsojYLpmwctoQx2wFGYCDlbPjMXg6c8Bio45PJ56p72EHQFTbGZDufqRA0MAr95HL6CCsjJDP+L4OulwmdAPHyv
        0Db/O6EtBPPteBWugFr6EPzOq2g0PNRtc5M082n2h8dFFsEKUAOaJxqYqdVdO29GMFO1EtaBj4/333101kjG59JMN70eDZPA
        U8XNRRWgiyrapHnaEngJDH22gzJ879aeT/aCQvv83j///wtFcz9mWnwvfKyWg6K7L/sPXcRpYH1E9ZEAAAAASUVORK5CYII=
        """
    )

    private static let codex = tintedMask(
        """
        iVBORw0KGgoAAAANSUhEUgAAACAAAAAgCAYAAABzenr0AAAAAXNSR0IArs4c6QAAADhlWElmTU0AKgAAAAgAAYdpAAQAAAAB
        AAAAGgAAAAAAAqACAAQAAAABAAAAIKADAAQAAAABAAAAIAAAAACPTkDJAAADZElEQVRYCa1WXYhNURg1D0Yp5YUHIlLDJCmF
        Iq8iIlEIKeVJSZGamkiRKPNASSmlpJQiKfKgkd8JIw+EaCaSvxDyz7DW8a3bsu8+916Zr9b9vr3W2t/Z9/zsc5oGNBZLYVsH
        jAB+AJ+AgUAz8BO4CywDqPV7nEPHN8A1YGHSvQnjNqAbeAlsAMYAywMTkf8rOjGb/7ajTpd26D3AM+A78DUyz8hH4Czwz8F/
        8ws4WGfmXugfgNfAaWAJMBzg5VoMnAH6APZaDzQc/Oc89WWxGgIPzMa3gVFAWVDjJaJ3Y5nJ+Z1h3uxk1GORH4f+Hpk3aKPx
        BUYuYlDZhK1hoIngTeZxHQNp+1xosB4d8+/n/Dzdaq7sPl5f8jedTGouSnN3J5qGD8KjcZF5t3Ki7tbOGCNVgho9ueBl0IF5
        7/BJ0HhRMmFNaPPE63pfFIHMOj3Y+QzHu12Lp5+blWI7Ci2CixoSwuDgt8W4YtKYuQtIF3Ap4bpjrIPw8cvFFZDyXEa9J8Z/
        LWBLMvNWmJy+EdzzyGzKutfGJ1DnYihIvyycO0tGDtK4AyLlxZEn5tik+cFJ41aci1Ug5TkmA4k0cnequFo7IzUdgJnXOxfy
        tFLMLaA3wz/KcKCqQs2VuWmlMRKE9KJoSRzvwrDD+IfBGZUt2fgtMA7QQZh5+j16MSBf/DxhYcFr6JP5CGmjMlu25LynphxA
        rV5GD5gcfEVMt12a9QJRA+Z6Qc+rxJTjaCn6TY2irPkk0+k5ApTFUQj08BJ65DjqlWNqnyexwGdare8DeogZprEWz/zZNJY5
        TnxhXRkmb1IImR/f2dzvNbdnD2rfnEC9HyBfxEn8cnAKeBE1x6xzwT2fukM+cRozk8stinwRPDAHvB8Y0wA1Yj5MMuIQsmuz
        JUSW5jS5PiP0RB0XtwkFTTwtHnpTqqnnsg8SebyPc3xCfFzxZclQ+c0nvacyo7qQh69fD/GeXS9qidOrlD9EM5Le6alF7wn1
        cH0CBuKZr7ro9UwzOl+r3mVz2HxtxswDUuNZrBsX4NBqx9dwTzEf/byJy0L9yvQqXl8+mtgGB18sLUB6U6Y7XtpMPbpSod54
        LgyaXJb5SVYr+Nxrbi1fTW0Y1A6An2M8YDtwD1Bj5lbAIz1LrvVbvQKdfBG5uqHT/hvUt3oTWPZjVQAAAABJRU5ErkJggg==
        """
    )

    private static let grok = tintedMask(
        """
        iVBORw0KGgoAAAANSUhEUgAAACAAAAAgCAYAAABzenr0AAAAAXNSR0IArs4c6QAAADhlWElmTU0AKgAAAAgAAYdpAAQAAAAB
        AAAAGgAAAAAAAqACAAQAAAABAAAAIKADAAQAAAABAAAAIAAAAACPTkDJAAAC1ElEQVRYCe2WTYhOYRTH75jBIAk1NCXX97eh
        CItZTEyR8rGwU2+zsBkf2SiNHclikiV2NCzHRlkRi2kWpKnxPUYRyULGVxYY/P7cc3veO3ee97mSt+TU733O85xznvN83Hvu
        G0X/pTonMJm0tUo9pgr5F5NzDnxT7r+9gNXk3AIP4DtEdfr5DWkkZgnMgnp4C4PwED5Cnqxg8AS0wZc8h5CxVpwuwWvQDlx0
        pI+hExZBDZhosc+hZANF2wYCLoCb0Kffw3dBkkR3/gQewbhkLG1CrmAe3t3QlEZF0Sv0XrgLH0ALXAszoStBO1byyzAXjsFn
        KCTT8O4D263uugOUKE8mOIO6hgGw2O2OLVg960zwDH1dYKSOXw+kJVfbHBibuq1B05Ep+D1sgBCZj1M2uebYGBLs+pyhYzs4
        6ho8upLbsfegD4HNUfLEjTBNYkRProLfQCNUEiVXjJ4TS3YI3RZwCj1YluFpx38lIErJn8JNUMExkW7zXLNBtx2tFM/AaWzi
        qHfaJwsxapGiBe6AyUsUXYNEb47N+XNAP3WpVq64jp/KTWW9pfROw3E4X2b51flKY2VXuUZseLQFvHMm02nkyXIG22E/9Oc5
        MDYlQWa9SbYY9b2i49LDpweoD7ILjRnbDUrgk20Y7SG86HPM2vQhuZoE6xg3OQ6q57HT96n6cNkC2nyOebY9TvAtdJXlIrIZ
        Zx25FqBvRwMUkpV4a/e2g8MFovX66WNksR0FYlPXVWjDySRdtFNTi1/ZgfkFWPIe9In+kHzrgWSSk7S1iYvardAJO0GvYQxN
        UALVAkus9j7EUFimE6GyesSJ1H+52+AmUJXTXzD3qsyuyhdDYdErpw/R3kykdnsOhsCS5LWD2A/CeKgoNRkPHfE+0B12Z2zW
        jVFaYT3MhnpQkRmAG3Ad3EJGN0yUfBc0h7n/WS/VaP0B0b/XqoiqW6WyWpWF/ftJfwAl17VRnFdZUgAAAABJRU5ErkJggg==
        """
    )

    private static func tintedMask(_ encoded: String) -> NSImage {
        let data = Data(base64Encoded: encoded, options: .ignoreUnknownCharacters)!
        let mask = NSImage(data: data)!
        let image = NSImage(size: NSSize(width: 13, height: 13), flipped: false) { bounds in
            mask.draw(in: bounds)
            NSColor.controlTextColor.setFill()
            bounds.fill(using: .sourceIn)
            return true
        }
        image.isTemplate = true
        return image
    }
}
