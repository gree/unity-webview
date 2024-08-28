window.addEventListener(
    'load',
    function() {
        document.body.style.backgroundColor = 'white';
        window.setTimeout(
            function() {
                document.body.style.backgroundColor = '#ABEBC6';
                var msg = document.getElementById("msg");
                msg.textContent = '(NOTE: the background color was changed by sample.js, for checking whether the external js code works)';
            },
            3000);
    });
function testSaveDataURL() {
    var canvas = document.createElement('canvas');
    canvas.width = 320;
    canvas.height = 240;
    var ctx = canvas.getContext("2d");
    ctx.fillStyle = "#fffaf0";
    ctx.fillRect(0, 0, 320, 240);
    ctx.fillStyle = "#000000";
    ctx.font = "48px serif";
    ctx.strokeText("Hello, world", 40, 132);
    Unity.saveDataURL("test.png", canvas.toDataURL());
    // NOTE: Unity.saveDataURL() for iOS cannot save a file under the common Downloads folder.
    // cf. https://github.com/gree/unity-webview/pull/904#issue-1650406563
};
