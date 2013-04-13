var unityWebView = 
{
    init : function (name) {
        $containers = $('.webviewContainer');
        if ($containers.size() === 0) {
            $('<div class="webviewContainer" style="overflow:hidden; position:relative; width:100%; height:100%; top:-100%; pointer-events:none;"></div>')
                .appendTo($('#unityPlayer'));
        }
        var $last = $containers.last();
        var clonedTop = parseInt($last.css('top')) - 100;
        var $clone = $last.clone().insertAfter($last).css('top', clonedTop + '%');
        var $iframe =
            $('<iframe style="position:relative; width:100%; height100%; border-style:none; display:none; pointer-events:auto;"></iframe>')
            .attr('id', 'webview_' + name)
            .appendTo($last)
            .load(function () {
                var contents = $(this).contents();
                var w = this.contentWindow;
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
        this.iframe(name)[0].contentWindow.location.replace(url);
    },

    evaluateJS: function (name, js) {
        this.iframe(name)[0].contentWindow.eval(js);
    },

    destroy: function (name) {
        this.iframe(name).remove();
    },

    iframe: function (name) {
        return $('#webview_' + name);
    },

};