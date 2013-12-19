class MainController extends KDController

  ###

  * EMITTED EVENTS
    - AppIsReady
    - AccountChanged                [account, firstLoad]
    - pageLoaded.as.loggedIn        [account, connectedState, firstLoad]
    - pageLoaded.as.loggedOut       [account, connectedState, firstLoad]
    - accountChanged.to.loggedIn    [account, connectedState, firstLoad]
    - accountChanged.to.loggedOut   [account, connectedState, firstLoad]

  ###

  connectedState =
    connected   : no

  constructor:(options = {}, data)->

    options.failWait  = 10000            # duration in miliseconds to show a connection failed modal

    super options, data

    @appStorages = {}

    @createSingletons()
    @setFailTimer()
    @attachListeners()

    @introductionTooltipController = new IntroductionTooltipController

  createSingletons:->

    KD.registerSingleton "mainController",            this
    KD.registerSingleton "appManager",   appManager = new ApplicationManager
    KD.registerSingleton "kiteController",            new KiteController
    KD.registerSingleton "vmController",              new VirtualizationController
    KD.registerSingleton "contentDisplayController",  new ContentDisplayController
    KD.registerSingleton "notificationController",    new NotificationController
    KD.registerSingleton "paymentController",         new PaymentController
    KD.registerSingleton "linkController",            new LinkController
    KD.registerSingleton 'router',           router = new KodingRouter
    KD.registerSingleton "localStorageController",    new LocalStorageController
    KD.registerSingleton "oauthController",           new OAuthController
    # KD.registerSingleton "fatih", new Fatih

    appManager.create 'Groups', (groupsController)->
      KD.registerSingleton "groupsController", groupsController

    appManager.create 'Chat', (chatController)->
      KD.registerSingleton "chatController", chatController

    @ready =>
      router.listen()
      KD.registerSingleton "activityController",      new ActivityController
      KD.registerSingleton "appStorageController",    new AppStorageController
      KD.registerSingleton "kodingAppsController",    new KodingAppsController
#      KD.registerSingleton "kontrol",                 new Kontrol
      @showInstructionsBook()
      @emit 'AppIsReady'

      console.timeEnd "Koding.com loaded"

  registerKodingClient: ->
    if registerToKodingClient = $.cookie "register-to-koding-client"
        clear = ->
          $.cookie "register-to-koding-client", erase:yes
          window.location.pathname = "/"

        # We pick up 54321 because it's in dynamic range and no one uses it
        # http://en.wikipedia.org/wiki/List_of_TCP_and_UDP_port_numbers
        k = new NewKite
          name: "kodingclient"
          publicIP: "127.0.0.1"
          port: "54321"

        k.connect()

        showErrorModal = (message, callback)->
          modal = new KDBlockingModalView
            title        : "Kite Registration"
            content      : "<div class='modalformline'>#{message}</div>"
            height       : "auto"
            overlay      : yes
            buttons      : {}

          Retry      =
            style    : "modal-clean-gray"
            callback : ->
              modal.destroy()
              callback?()

          Cancel     =
            style    : "modal-clean-red"
            callback : ->
              modal.destroy()
              clear()

          Ok         =
            style    : "modal-clean-gray"
            callback : ->
              modal.destroy()
              clear()

          if /^Authentication\ already\ established/.test message
            modal.setButtons {Ok}, yes
          else
            modal.setButtons {Retry, Cancel}, yes

        showSuccessfulModal = (message, callback)->
          modal = new KDBlockingModalView
            title        : "Koding Client Registration"
            content      : "<div class='modalformline'>#{message}</div>"
            height       : "auto"
            overlay      : yes
            buttons      :
              Ok         :
                style    : "modal-clean-green"
                callback : ->
                  modal.destroy()
                  callback?()

        handleInfo = (err, result)=>
          KD.remote.api.JKodingKey.registerHostnameAndKey {
              key:result.key
              hostname:result.hostID
          }, (err, res)=>
            fn = => k.tell "info", handleInfo
            return showErrorModal err.message, fn if err
            showSuccessfulModal res, =>
              result.cb true
              KD.utils.wait 500, clear

        k.tell "info", handleInfo

  accountChanged:(account, firstLoad = no)->
    @userAccount             = account
    connectedState.connected = yes

    @on "pageLoaded.as.loggedIn", (account)=> # ignore othter parameters
      KD.utils.setPreferredDomain account if account
      @emit "changedToLoggedIn"

    @once "accountChanged.to.loggedIn", (account)=> # ignore othter parameters
      @emit "changedToLoggedIn"

    account.fetchMyPermissionsAndRoles (err, permissions, roles)=>
      return warn err  if err
      KD.config.roles       = roles
      KD.config.permissions = permissions

      @ready @emit.bind this, "AccountChanged", account, firstLoad

      @createMainViewController()  unless @mainViewController

      @emit 'ready'

      # this emits following events
      # -> "pageLoaded.as.loggedIn"
      # -> "pageLoaded.as.loggedOut"
      # -> "accountChanged.to.loggedIn"
      # -> "accountChanged.to.loggedOut"
      eventPrefix = if firstLoad then "pageLoaded.as" else "accountChanged.to"
      eventSuffix = if @isUserLoggedIn() then "loggedIn" else "loggedOut"
      @emit "#{eventPrefix}.#{eventSuffix}", account, connectedState, firstLoad

  createMainViewController:->
    @loginScreen = new LoginView
      testPath   : "landing-login"
    @loginScreen.appendToDomBody()
    @mainViewController  = new MainViewController
      view    : mainView = new MainView
        domId : "kdmaincontainer"
    mainView.appendToDomBody()

  doLogout:->
    mainView = KD.getSingleton("mainView")
    KD.logout()
    storage = new LocalStorage 'Koding'
    KD.remote.api.JUser.logout (err, account, replacementToken)=>
      mainView._logoutAnimation()
      KD.utils.wait 1000, ->
        $.cookie 'clientId', replacementToken  if replacementToken
        storage.setValue 'loggingOut', '1'
        location.reload()

  attachListeners:->
    # @on 'pageLoaded.as.(loggedIn|loggedOut)', (account)=>
    #   log "pageLoaded", @isUserLoggedIn()

    @once 'changedToLoggedIn', (account)=>
      @registerKodingClient()

    # TODO: this is a kludge we needed.  sorry for this.  Move it someplace better C.T.
    wc = @getSingleton 'windowController'
    @utils.wait 15000, ->
      KD.remote.api?.JSystemStatus.on 'forceReload', ->
        window.removeEventListener 'beforeunload', wc.bound 'beforeUnload'
        location.reload()

    # async clientId change checking procedures causes
    # race conditions between window reloading and post-login callbacks
    @utils.repeat 3000, do (cookie = $.cookie 'clientId') => =>
      cookieExists = cookie?
      cookieMatches = cookie is ($.cookie 'clientId')
      cookie = $.cookie 'clientId'
      if cookieExists and not cookieMatches
        return @isLoggingIn off  if @isLoggingIn() is on

        window.removeEventListener 'beforeunload', wc.bound 'beforeUnload'
        @emit "clientIdChanged"

        # window location path is set to last route to ensure visitor is not
        # redirected to another page
        @utils.defer ->
          firstRoute = KD.getSingleton("router").visitedRoutes.first

          if firstRoute and /^\/Verify/.test firstRoute
            firstRoute = "/"

          window.location.pathname = firstRoute or "/"

  setVisitor:(visitor)-> @visitor = visitor
  getVisitor: -> @visitor
  getAccount: -> KD.whoami()

  isUserLoggedIn: -> KD.isLoggedIn()

  isLoggingIn: (isLoggingIn) ->

    storage = new LocalStorage 'Koding'
    if storage.getValue('loggingOut') is '1'
      storage.unsetKey 'loggingOut'
      return yes
    if isLoggingIn?
      @_isLoggingIn = isLoggingIn
    else
      @_isLoggingIn ? no

  showInstructionsBook:->
    if $.cookie 'newRegister'
      @emit "ShowInstructionsBook", 9
      $.cookie 'newRegister', erase: yes
    else if @isUserLoggedIn()
      BookView::getNewPages (pages)=>
        return unless pages.length
        BookView.navigateNewPages = yes
        @emit "ShowInstructionsBook", pages.first.index

  setFailTimer: do->
    modal = null
    fail  = ->
      modal = new KDBlockingModalView
        title   : "Couldn't connect to the backend!"
        content : "<div class='modalformline'>
                     We don't know why, but your browser couldn't reach our server.<br><br>Please try again.
                   </div>"
        height  : "auto"
        overlay : yes
        buttons :
          "Refresh Now" :
            style       : "modal-clean-red"
            callback    : ->
              modal.destroy()
              location.reload yes
      # if location.hostname is "localhost"
      #   KD.utils.wait 5000, -> location.reload yes

    checkConnectionState = ->
      unless connectedState.connected
        fail()

    return ->
      @utils.wait @getOptions().failWait, checkConnectionState
      @on "AccountChanged", =>
        if modal
          modal.setTitle "Connection Established"
          modal.$('.modalformline').html "<b>It just connected</b>, don't worry about this warning."
          modal.buttons["Refresh Now"].destroy()

          @utils.wait 2500, -> modal?.destroy()
