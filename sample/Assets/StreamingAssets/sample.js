window.addEventListener(
    'load',
    function() {
        // cf. https://www.aedi.jp/work/webrtc/
        var constraints = { audio: true, video: { facingMode: "user" } };
        navigator.mediaDevices
            .getUserMedia(constraints)
            .then(function(mediaStream) {
                var video = document.querySelector('video');
                video.srcObject = mediaStream;
                video.onloadedmetadata = function(e) {
                    video.play();
                };
            })
            .catch(function(err) { console.log(err.name + ": " + err.message); });
    });
