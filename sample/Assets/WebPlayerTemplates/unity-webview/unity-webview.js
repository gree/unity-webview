var unityWebView = 
{
    loaded: [],

    init : function (name) {
        $containers = $('.webviewContainer');
        if ($containers.length === 0) {
            $('<div style="position: absolute; left: 0px; width: 100%; height: 100%;"><div class="webviewContainer" style="overflow:hidden; position:relative; width:100%; height:100%; top:-100%; pointer-events:none; z-index: 1;"></div></div')
                .appendTo($('#unityPlayer'));
        }
        var $last = $('.webviewContainer:last');
        var clonedTop = parseInt($last.css('top')) - 100;
        var $clone = $last.clone().insertAfter($last).css('top', clonedTop + '%');
        var $iframe =
            $('<iframe style="position:relative; width:100%; height100%; border-style:none; display:none; pointer-events:auto;"></iframe>')
            .attr('id', 'webview_' + name)
            .appendTo($last)
            .on('load', function () {
                $(this).attr('loaded', 'true');
                var contents = $(this).contents();
                var w = $(this)[0].contentWindow;
                contents.find('a').click(function (e) {
                    var href = $.trim($(this).attr('href'));
                    if (href.substr(0, 6) === 'unity:') {
                        u.getUnity().SendMessage(name, "CallFromJS", href.substring(6, href.length));
                        e.preventDefault();
                    } else {
                        w.location.replace(href);
                    }
                });

                contents.find('form').submit(function () {
                    $this = $(this);
                    var action = $.trim($this.attr('action'));
                    if (action.substr(0, 6) === 'unity:') {
                        var message = action.substring(6, action.length);
                        if ($this.attr('method').toLowerCase() == 'get') {
                            message += '?' + $this.serialize();
                        }
                        u.getUnity().SendMessage(name, "CallFromJS", message);
                        return false;
                    }
                    return true;
                }); 
            });
    },

    sendMessage: function (name, message) {
        u.getUnity().SendMessage(name, "CallFromJS", message);
    },

    setMargins: function (name, left, top, right, bottom) {
        var $player = $('#unityPlayer');
        var width = $player.width();
        var height = $player.height();

        var lp = left / width * 100;
        var tp = top / height * 100;
        var wp = (width - left - right) / width * 100;
        var hp = (height - top - bottom) / height * 100;

        this.iframe(name)
            .css('left', lp + '%')
            .css('top', tp + '%')
            .css('width', wp + '%')
            .css('height', hp + '%');
    },

    setVisibility: function (name, visible) {
        if (visible)
            this.iframe(name).show();
        else
            this.iframe(name).hide();
    },

    loadURL: function(name, url) {
        this.iframe(name).attr('loaded', 'false')[0].contentWindow.location.replace(url);
    },

    evaluateJS: function (name, js) {
        $iframe = this.iframe(name);
        if ($iframe.attr('loaded') === 'true') {
            $iframe[0].contentWindow.eval(js);
        } else {
            $iframe.on('load', function(){
                $(this)[0].contentWindow.eval(js);
            });
        }
    },

    destroy: function (name) {
        this.iframe(name).parent().parent().remove();
    },

    iframe: function (name) {
        return $('#webview_' + name);
    },

};
