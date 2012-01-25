/**
 * Dh-proto-proof ui controller
 * @author Cedric Staub
 */

/*-----------------------------------------------------------*
 * Theory state                                              *
 *-----------------------------------------------------------*/

var theory = {
    /**
     * Convert a relative path into an absolute one.
     * @param section Section/display, for example main or debug.
     * @param path The relative path.
     * @return The absolute path.
     */
    absolutePath: function(section, path) {
        return "/thy/" + this.idx + "/" + section + "/" + path;
    }
}

/*-----------------------------------------------------------*
 * Backend/server communication                              *
 *-----------------------------------------------------------*/

var server = {
    /**
     * Perform an ASR (asynchronous request) to the server.
     * @param path      The path to request (absolute!).
     * @param dataType  The data to request (xml, html, json).
     * @param cache     Should we cache? True/false.
     * @param success   The callback function on success.
     * @param error     The callback function on error.
     */
    performASR: function(path, dataType, cache, success, error) {
        loadingScreen.show(path);

        $.ajax({
            url: path,
            dataType: dataType,
            cache: cache,
            success: function(data, textStatus) {
                loadingScreen.reset();
                success(data, textStatus);
            },
            error: function(data, textStatus, err) {
                loadingScreen.reset();
                error(data, textStatus, err);
            }
        });
    },

    /**
     * Process JSON response from server.
     * @param path  The path that was loaded.
     * @param data  The data that was received.
     * @param html  Callback for html data.
     */
    handleJson: function(data, html) {
        // Parse resulting json
        if(data.redirect) {
            // Server wants redirect
            loadingScreen.show(data.redirect);
            window.location.href = data.redirect;
        } else if(data.alert) {
            // Server requested alert box
            ui.showDialog(data.alert);
        } else {
            // It must be a html response.
            html(data.title, data.html);
        }
    },
}

/*-----------------------------------------------------------*
 * Loading screen                                            *
 *-----------------------------------------------------------*/

var loadingScreen = {
    /**
     * Cancel a request by sending a kill request to the server.
     * @param path The original request path.
     */
    cancel: function(path) {
        server.performASR(
            "/kill?path=" + encodeURIComponent(path),
            "text",
            false,
            // Success callback
            function(data, textStatus) {
                ui.showDialog(data);
            },
            // Error callback
            function(data, textStatus, err) {
                ui.showDisplay("Unable to cancel request! Is server down?");
            });
    },

    /**
     * Show the loading notification in the main view.
     * @param path The target of the link which is loading.
     */
    show: function(path) {
        // Display loading screen
        var display = $("p.loading");
        display.hide().fadeIn(1000);
    
        // Install cancel click handler
        display.children("a#cancel").unbind('click').click(function() {
            loadingScreen.cancel(path);
        });
    },

    /**
     * Reset the loading display.
     */
    reset: function() {
        var display = $("p.loading");
        display.stop(true, true);
        display.hide();
    }
}

/*-----------------------------------------------------------*
 * User interface                                            *
 *-----------------------------------------------------------*/

var ui = {
    /**
     * Initialize various aspects of the user interface.
     */
    init: function() {
        // Load display settings
        this.loadSettings();

        // Navigation drop-down menus
        $("ul#navigation").superfish();

        // Add keyboard shortcuts
        var shortcuts = {
            74  : function() { proofScript.jump('next/smart', null); },
            75  : function() { proofScript.jump('prev/smart', null); },
            106 : function() { proofScript.jump('next/normal', null); },
            107 : function() { proofScript.jump('prev/normal', null); }
        }

        for(i = 1; i < 10; i++) {
            shortcuts[i + 48] = function(key) {
                mainDisplay.applyProofMethod(key - 48);
            };
        }

        this.add_shortcuts(shortcuts);

        // Initialize dialog box
        $("div#dialog").dialog({
            autoOpen: false,
            title: 'Message',
            width: '30em',
            buttons: {
                "Ok": function() {
                    $(this).dialog("close");
                 }
            }
        });

        // Enable context menu
        $("#proof a.proof-step").contextMenu(
            { menu: "contextMenu" },
            function(action, el, pos) {
                mainDisplay.loadTarget(
                    action,
                    $(el).attr("href"),
                    function() {
                        var path = $(el).attr("href");
                        $.cookie("last-target", path, { path: "/" });
                        $.cookie("jump-to-target", true, { path: "/" });
                    });
            });

        // Click handler for save link
        events.installAbsoluteClickHandler("a.save-link", server.handleJson);

        // Click handler for edit link(s)
        events.installAbsoluteClickHandler(
            "a.edit-link",
             function(data, textStatus) {
                 server.handleJson(data, mainDisplay.setContent);
                 events.installFormHandler();
             });

        // Click handler for debug pane toggle
        var debug_toggle = $("a#debug-toggle");
        debug_toggle.click(function(ev) {
            ev.preventDefault();
            layout.toggle("east");
            mainDisplay.toggleOption(debug_toggle);
        });
        
        // Click handler for graph toggle
        var graph_toggle = $('a#graph-toggle');
        graph_toggle.click(function(ev) {
            ev.preventDefault();
            if($.cookie("uncompact-graphs")) {
                $.cookie("uncompact-graphs", null, { path: '/' });
            } else {
                $.cookie("uncompact-graphs", true, { path: '/' });
            }
            $("a.active-link").click();
            mainDisplay.toggleOption(graph_toggle);
        });
    
        // Click handler for sequent compression toggle
        var sequent_toggle = $('a#seqnt-toggle');
        sequent_toggle.click(function(ev) {
            ev.preventDefault();
            if($.cookie("uncompress-sequents")) {
                $.cookie("uncompress-sequents", null, { path: '/' });
            } else {
                $.cookie("uncompress-sequents", true, { path: '/' });
            }
            $("a.active-link").click();
            mainDisplay.toggleOption(sequent_toggle);
        });

        // Install event handlers
        events.installScrollHandler(
            "west",
            "div.ui-layout-west div.scroll-wrapper");
    
        // Install handlers on plain internal links
        events.installRelativeClickHandler(
            "div#proof a.internal-link",
            "main",
            null);
    
        // Install handlers on edit links (lemma)
        events.installRelativeClickHandler(
            "div#proof a.internal-link.edit-link",
            "edit/path",
            function(el) {
                events.installFormHandler();
            });
    
        // Install handlers on delete links
        events.installRelativeClickHandler(
            "div#proof a.internal-link.delete-link",
            "del/path",
            null);
    
        // Install handlers on proof-step links
        events.installRelativeClickHandler(
            "div#proof a.internal-link.proof-step",
            "main",
            function(el) {
                var path = $(el).attr("href");
                $.cookie("last-target", path, { path: "/" });
                $.cookie("jump-next-open-goal", true, { path: "/" });
            });
    
        // Install handlers on removal links
        events.installRelativeClickHandler(
            "div#proof a.internal-link.remove-step",
            "del/path",
            function(el) {
                var path = $(el).attr("href");
                $.cookie("last-target", path, { path: "/" });
                $.cookie("jump-to-target", true, { path: "/" });
            });
    },

    /**
     * Load viewing settings from cookie.
     */
    loadSettings: function() {
        if($.cookie("east-size")) {
            layout.sizePane("east", $.cookie("east-size"));
        }
    
        if($.cookie("east-open")) {
            layout.open("east");
            $("a#debug-toggle").addClass("active-option");
        } else {
            layout.close("east");
            $("a#debug-toggle").addClass("inactive-option");
        }
    
        if($.cookie("west-size")) {
            layout.sizePane("west", $.cookie("west-size"));
        } else {
            layout.sizePane("west", 475);
        }
    
        if($.cookie("west-position")) {
            var pos = $.cookie("west-position");
            $("div.ui-layout-west div.scroll-wrapper").scrollTop(pos);
        }
    
        if($.cookie("uncompress-sequents")) {
            $("a#seqnt-toggle").addClass("inactive-option");
        } else {
            $("a#seqnt-toggle").addClass("active-option");
        }
    
        if($.cookie("uncompact-graphs")) {
            $("a#graph-toggle").addClass("inactive-option");
        } else {
            $("a#graph-toggle").addClass("active-option");
        }
    },

    /**
     * Add keyboard shortcut(s) from map.
     * @param map Map of { key : callback } pairs.
     */
    add_shortcuts: function(map) {
        $("html").keypress(function(ev) {
            var key = ev.which;
            var tag = ev.target.tagName.toLowerCase();

            // Don't trigger on input/textarea
            if(tag == 'input' || tag == 'textarea') return;

            // If key is in map, call the given
            // callback function and pass keycode
            if(map[key]) {
                // Hide context menu
                $("ul#contextMenu").hide();
                // Call callback
                var callback = map[key];
                callback(key);
            }
        });
    },

    /**
     * Show dialog
     * @param msg The message.
     */
    showDialog: function(msg) {
        var dialog = $("div#dialog");
        dialog.html(msg.replace("\n","<br>"));
        dialog.dialog('open');
    }
}


/*-----------------------------------------------------------*
 * Event handlers and callback functions                     *
 *-----------------------------------------------------------*/

var events = {
    /**
     * Install handler for scroll event for storing state.
     * @param name Name to store setting in cookie as.
     * @param selector The CSS selector for the container.
     */
    installScrollHandler: function(name, selector) {
        $(selector).scroll(function(ev) {
            // Hide context menu
            $("ul#contextMenu").hide();
            // Record position in cookie
            var pos = $(this).scrollTop();
            $.cookie(name + "-position", pos, { path: "/" });
        });
    },

    /**
     * Install click handler for absolute link.
     * @param selector The css selector.
     * @param callback The callback function.
     */
    installAbsoluteClickHandler: function(selector, callback) {
        $(selector).click(function(ev) {
            ev.preventDefault();

            var link = $(this);
            var path = link.attr("href");

            server.performASR(
                path,
                "json",
                false,
                callback,
                function(data, textStatus, err) {
                    ui.showDialog("Unable to load view! Is server down?");
                });
        });
    },

    /**
     * Install click handler for relative links.
     * @param selector The CSS selector to use.
     */
    installRelativeClickHandler: function(selector, section, callback) {
        // Remove (possible) old click handler(s)
        $(selector).unbind('click');
        // Add new click handler
        $(selector).click(function(ev) { 
            ev.preventDefault();
            var element = $(this);
            mainDisplay.loadTarget(
                section,
                element.attr("href"),
                function() {
                    if(callback) callback(element);
                });
        });
    },

    /**
     * Install form handler.
     */
    installFormHandler: function() {
        var form = $("#ui-main-display form");
        var path = form.attr("action");
        var submit = form.find("input[type='submit']");
        var cancel = form.find("input[id='cancel-form']");

        cancel.click(function(ev) {
            ev.preventDefault();
            if($.cookie("last-target")) {
                mainDisplay.loadTarget("main", $.cookie("last-target"));
            } else {
                mainDisplay.loadTarget("main", "rules");
            }
        });

        submit.click(function(ev) {
            ev.preventDefault();
            loadingScreen.show(path);
            $.ajax({
                type: "POST",
                url: path,
                data: form.serialize(),
                dataType: "json",
                success: function(data, textStatus) {
                    loadingScreen.reset();
                    server.handleJson(data, mainDisplay.setContent);
                }
            });
        });
    },

}

/*-----------------------------------------------------------*
 * Proof script display                                      *
 *-----------------------------------------------------------*/

var proofScript = {
    /**
     * Focus the active link by scrolling to it.
     */
    focusActive: function() {
        var element = $("#proof");
        var wrapper = $("#proof-wrapper");
        var selector = "a.active-link";
        var link = element.find(selector).first();

        if(link.length > 0) {
            // Calculate new position
            var pos = wrapper.scrollTop();
            var contOffset = wrapper.offset().top;
            var linkOffset = link.offset().top;
            var height = wrapper.height();
            var newPos = pos + linkOffset - (height/2) - (contOffset/2);
        
            // Now scroll there
            wrapper.stop(true, true);
            wrapper.animate(
                { scrollTop: newPos },
                { duration: 'fast', easing: 'swing' }
            );
        }
    },

    /**
     * Jump to new target. Server decides where depending on arguments.
     * @param mode For example 'next/normal' or 'prev/smart'.
     * @param err_callback Callback on error.
     */
    jump: function(mode, err_callback) {
        var element = $("#proof");
        var active = element.find("a.active-link").first();
    
        if(active.length > 0) {
            var current = active.attr("href"); 
    
            server.performASR(
                theory.absolutePath(mode, current),
                "text",
                false,
                // Success callback
                function(data, textStatus) {
                    var selector = "a.internal-link[href='" + data + "']";
                    var link = element.find(selector);

                    if(link.length > 0) {
                        mainDisplay.loadTarget(
                            "main",
                            link.attr("href"),
                            function() {
                                proofScript.focusActive();
                            }
                        );
                    } else if(err_callback != null) {
                        err_callback();
                    }
                },
                // Error callback
                function(data, textStatus, error) {
                    if(err_callback != null) err_callback();
                });
        } else {
            $("div#proof a.internal-link").first().click();
        }
    },

    /**
     * Just jump to next open goal or case if no open goal.
     * @param target Jump relative to this target.
     */
    jumpNextOpenGoal: function(target) {
        this.focusTarget(target);
        // Perform smart jump
        proofScript.jump('next/smart', function() {
            // If smart jump failed (e.g. there are
            // no more open goals), perform normal jump
            proofScript.jump('next/normal', function() {
                // If both failed, just jump to target
                proofScript.jumpToTarget(target);
            });
        });
    },

    /**
     * Jump to a given target.
     * @param target The target.
     */
    jumpToTarget: function(target) {
        this.focusTarget(target).click();
    },

    /**
     * Focus a given target.
     * @param target The target.
     */
    focusTarget: function(target) {
        var element = $("#proof");
        var selector = "a.proof-step.[href='" + target + "']";
        var link = element.find(selector)
        link.addClass("active-link");
        return link;
    }
}

/*-----------------------------------------------------------*
 * Main display                                              *
 *-----------------------------------------------------------*/

var mainDisplay = {
    /**
     * Apply a proof method.
     * @param num Number of proof method to apply (1-9).
     */
    applyProofMethod: function(num) {
        var path = $("a.active-link").attr("href");
        $.cookie("last-target", path, { path: "/" });
        $.cookie("jump-next-open-goal", true, { path: "/" });

        var element = $("#ui-main-display");
        var methods = element.find("div.methods a.internal-link");

        if(methods.length >= num) {
            $(methods.get([ num - 1 ])).click();
        }
    },

    /**
     * Update main view with new HTML data.
     * @param html_data The html data.
     */
    setContent: function(title, html_data) {
        if(title) $("#main-title").html(title);

        var element = $("#ui-main-display");
        var wrapper = $("#main-wrapper");

        // Received html, display it
        element.html(html_data);
        
        // Get image settings from cookie
        var params = []
        if($.cookie("uncompact-graphs")) {
            params = params.concat(
                { name: "uncompact", value: "" }
            );
        }
        if($.cookie("uncompress-sequents")) {
            params = params.concat(
                { name: "uncompress", value: "" }
            );
        }
        
        // Rewrite image paths (if necessary)
        if(params.length > 0) {
            var query_string = $.param(params);
            element.find("img").each(function(idx, elem) {
                var img = $(elem);
                var path = img.attr("src") + "?" + query_string;
                img.attr("src", path);
            });
        }
        
        // Focus main view (so PgUp/PgDown works)
        wrapper.focus();
    
        // Re-install click handlers on main
        events.installRelativeClickHandler(
            "div#ui-main-display a.internal-link",
            "main",
            null);
    },

    /**
     * Load a given target.
     * @param target The target to load.
     * @param callback Optional callback to call after successful load.
     */
    loadTarget: function(section, target, callback) {
        // Load main view
        server.performASR(
            theory.absolutePath(section, target),
            "json",
            false,
            // Success callback
            function(data, textStatus) {
                // Handle JSON reponse
                server.handleJson(data, function(title, html_data) {
                    mainDisplay.setContent(title, html_data);
    
                    // Set active-link class for target
                    var selector = "a.internal-link[href='" + target + "']";
                    $("a.active-link").removeClass("active-link");
                    $(selector).first().addClass("active-link");
    
                    /*
                    // Load debug view
                    server.performASR(
                        theory.absolutePath('debug', target),
                        "html",
                        false,
                        // Success callback
                        function(data, textStatus) {
                            $("#ui-debug-display").html(data);
                        }
                    );
                    */
                });
    
                // Call optional callback
                if(callback) callback();
            },
            // Error callback
            function(data, textStatus, error) {
                ui.showDialog("Unable to load view! Is server down?");
            }
        );
    },

    /**
     * Toggle active/inactive option classes
     * @param obj Jquery-wrapped object to operate on.
     */
    toggleOption: function(obj) {
        if(obj.hasClass('active-option')) {
            obj.removeClass('active-option');
            obj.addClass('inactive-option');
        } else {
            obj.removeClass('inactive-option');
            obj.addClass('active-option');
        }
    }
}

/*-----------------------------------------------------------*
 * Main initialization function.                             *
 *-----------------------------------------------------------*/

/**
 * Initialize when document is ready.
 */
$(document).ready(function() {
    // Automatically submit upload form on root
    $("input[type=file]").change(function() {
        var obj = $(this);
        if(obj.val()) {
            obj.parents("form").submit(); 
        }
    });

    // Only run rest of script if the main display is available
    var main_display = $("#ui-main-display");
    if(main_display.length != 1) return;

    // Get theory index
    theory.idx = location.pathname.split('/')[2];

    // Set up the layout
    layout = $('body').layout({
        // Options
        north__spacing_open: 0,
        east__spacing_closed: 0,
        east__spacing_open: 4,
        west__spacing_open: 4,
        east__initClosed: true,

        // Callbacks (store state in cookie)
        onopen: function(name, elem, state, opts, layout) {
            $.cookie(name + "-open", true, { path: '/' });
        },
        onclose: function(name, elem, state, opts, layout) {
            $.cookie(name + "-open", null, { path: '/' });
        },
        onresize: function(name, elem, state, opts, layout) {
            $.cookie(name + "-size", elem.width(), { path: '/' });
        },
    });
    
    // Initialize user interface
    ui.init();

    // Process jump instructions
    if($.cookie("jump-to-target")) {
        if($.cookie("last-target")) {
            proofScript.jumpToTarget($.cookie("last-target"));
        }
        $.cookie("jump-to-target", null, { path: "/" });
    } else if($.cookie("jump-next-open-goal")) {
        if($.cookie("last-target")) {
            proofScript.jumpNextOpenGoal($.cookie("last-target"));
        }
        $.cookie("jump-next-open-goal", null, { path: "/" });
    }

});