class App.TicketZoom extends App.Controller
  events:
    'click .submit': 'submit'

  constructor: (params) ->
    super

    # check authentication
    return if !@authenticate()

    @navupdate '#'

    @form_meta      = undefined
    @ticket_id      = params.ticket_id
    @article_id     = params.article_id
    @signature      = undefined

    @key = 'ticket::' + @ticket_id
    cache = App.Store.get( @key )
    if cache
      @load(cache)
    update = =>
      @fetch( @ticket_id, false )
    @interval( update, 450000, 'pull_check' )

    # fetch new data if triggered
    @bind(
      'Ticket:update'
      (data) =>
        update = =>
          if data.id.toString() is @ticket_id.toString()
            @log 'notice', 'TRY', new Date(data.updated_at), new Date(@ticketUpdatedAtLastCall)
            if !@ticketUpdatedAtLastCall || ( new Date(data.updated_at).toString() isnt new Date(@ticketUpdatedAtLastCall).toString() )
              @fetch( @ticket_id, false )
        @delay( update, 1800, 'ticket-zoom-' + @ticket_id )
    )

  meta: =>
    meta =
      url:        @url()
      id:         @ticket_id
      iconClass:  "priority"
    if @ticket
      @ticket = App.Ticket.fullLocal( @ticket.id )
      meta.head  = @ticket.title
      meta.title = '#' + @ticket.number + ' - ' + @ticket.title
      meta.class  = "level-#{@ticket.level()}"
    meta

  url: =>
    '#ticket/zoom/' + @ticket_id

  activate: =>
    App.OnlineNotification.seen( 'Ticket', @ticket_id )
    @navupdate '#'

  changed: =>
    formCurrent = @formParam( @el.find('.edit') )
    ticket = App.Ticket.find(@ticket_id).attributes()
    modelDiff  = @getDiff( ticket, formCurrent )
    return false if !modelDiff || _.isEmpty( modelDiff )
    return true

  release: =>
    # nothing
    @autosaveStop()

  fetch: (ticket_id, force) ->

    return if !@Session.get()

    # get data
    @ajax(
      id:    'ticket_zoom_' + ticket_id
      type:  'GET'
      url:   @apiPath + '/ticket_full/' + ticket_id
      processData: true
      success: (data, status, xhr) =>

        # check if ticket has changed
        newTicketRaw = data.assets.Ticket[ticket_id]
        if @ticketUpdatedAtLastCall && !force

          # return if ticket hasnt changed
          return if @ticketUpdatedAtLastCall is newTicketRaw.updated_at

          # notify if ticket changed not by my self
          if newTicketRaw.updated_by_id isnt @Session.get('id')
            App.TaskManager.notify( @task_key )

          # rerender edit box
          @editDone = false

        # remember current data
        @ticketUpdatedAtLastCall = newTicketRaw.updated_at

        @load(data, force)
        App.Store.write( @key, data )

      error: (xhr, status, error) =>

        # do not close window if request is aborted
        return if status is 'abort'

        # do not close window on network error but if object is not found
        return if status is 'error' && error isnt 'Not Found'

        # remove task
        App.TaskManager.remove( @task_key )
    )

    if !@doNotLog
      @doNotLog = 1
      @recentView( 'Ticket', ticket_id )

  load: (data, force) =>

    # remember article ids
    @ticket_article_ids = data.ticket_article_ids

    # remember link
    @links = data.links

    # remember tags
    @tags = data.tags

    # get edit form attributes
    @form_meta = data.form_meta

    # get signature
    @signature = data.signature

    # load assets
    App.Collection.loadAssets( data.assets )

    # get data
    @ticket = App.Ticket.fullLocal( @ticket_id )

    # render page
    @render(force)

  render: (force) =>

    # update taskbar with new meta data
    App.Event.trigger 'task:render'
    @formEnable( @$('.submit') )

    if !@renderDone
      @renderDone = true
      @html App.view('ticket_zoom')(
        ticket:     @ticket
        nav:        @nav
        isCustomer: @isRole('Customer')
      )
      @TicketTitle()

      editTicket = (el) =>
        el.append('<form class="edit"></form>')
        @editEl = el
        console.log('EDIT TAB', @ticket.id)

        reset = (e) =>
          e.preventDefault()
          App.TaskManager.update( @task_key, { 'state': {} })
          show(@ticket)

        show = (ticket) =>
          console.log('SHOW', ticket.id)
          el.find('.edit').html('')

          formChanges = (params, attribute, attributes, classname, form, ui) =>
            if @form_meta.dependencies && @form_meta.dependencies[attribute.name]
              dependency = @form_meta.dependencies[attribute.name][ parseInt(params[attribute.name]) ]
              if dependency

                for fieldNameToChange of dependency
                  filter = []
                  if dependency[fieldNameToChange]
                    filter = dependency[fieldNameToChange]

                  # find element to replace
                  for item in attributes
                    if item.name is fieldNameToChange
                      item.display = false
                      item['filter'] = {}
                      item['filter'][ fieldNameToChange ] = filter
                      item.default = params[item.name]
                      #if !item.default
                      #  delete item['default']
                      newElement = ui.formGenItem( item, classname, form )

                  # replace new option list
                  form.find('[name="' + fieldNameToChange + '"]').replaceWith( newElement )

          defaults   = ticket.attributes()
          task_state = App.TaskManager.get(@task_key).state || {}
          modelDiff  = @getDiff( defaults, task_state )
          #if @isRole('Customer')
          #  delete defaults['state_id']
          #  delete defaults['state']
          if !_.isEmpty( task_state )
            defaults = _.extend( defaults, task_state )

          new App.ControllerForm(
            el:         el.find('.edit')
            model:      App.Ticket
            screen:     'edit'
            params:     App.Ticket.find(ticket.id)
            handlers: [
              formChanges
            ]
            filter:    @form_meta.filter
            params:    defaults
          )
          #console.log('Ichanges', modelDiff, task_state, ticket.attributes())
          @markFormDiff( modelDiff )

          # bind on reset link
          @el.find('.edit .js-reset').on(
            'click'
            (e) =>
              reset(e)
          )

        @subscribeIdEdit = @ticket.subscribe(show)
        show(@ticket)

        if !@isRole('Customer')
          el.append('<div class="tags"></div>')
          new App.WidgetTag(
            el:           el.find('.tags')
            object_type:  'Ticket'
            object:       @ticket
            tags:         @tags
          )
          el.append('<div class="links"></div>')
          new App.WidgetLink(
            el:           el.find('.links')
            object_type:  'Ticket'
            object:       @ticket
            links:        @links
          )
          el.append('<div class="action"></div>')
          showHistory = =>
            new App.TicketHistory( ticket_id: @ticket.id )
          showMerge = =>
            new App.TicketMerge( ticket: @ticket, task_key: @task_key )
          actions = [
            {
              name:     'history'
              title:    'History'
              callback: showHistory
            },
            {
              name:     'merge'
              title:    'Merge'
              callback: showMerge
            },
          ]
          new App.ActionRow(
            el:    @el.find('.action')
            items: actions
          )

      items = [
        {
          head: 'Ticket Settings'
          name: 'ticket'
          icon: 'message'
          callback: editTicket
        }
      ]
      if !@isRole('Customer')
        editCustomer = (e, el) =>
          new App.ControllerGenericEdit(
            id: @ticket.customer_id
            genericObject: 'User'
            screen: 'edit'
            pageData:
              title: 'Users'
              object: 'User'
              objects: 'Users'
          )
        changeCustomer = (e, el) =>
          new App.TicketCustomer(
            ticket: @ticket
          )
        showCustomer = (el) =>
          new App.WidgetUser(
            el:       el
            user_id:  @ticket.customer_id
          )
        items.push {
          head: 'Customer'
          name: 'customer'
          icon: 'person'
          actions: [
            {
              name:  'Change Customer'
              class: 'glyphicon glyphicon-transfer'
              callback: changeCustomer
            },
            {
              name:  'Edit Customer'
              class: 'glyphicon glyphicon-edit'
              callback: editCustomer
            },
          ]
          callback: showCustomer
        }
        if @ticket.organization_id
          editOrganization = (e, el) =>
            new App.ControllerGenericEdit(
              id: @ticket.organization_id,
              genericObject: 'Organization'
              pageData:
                title: 'Organizations'
                object: 'Organization'
                objects: 'Organizations'
            )
          showOrganization = (el) =>
            new App.WidgetOrganization(
              el:               el
              organization_id:  @ticket.organization_id
            )
          items.push {
            head: 'Organization'
            name: 'organization'
            icon: 'group'
            actions: [
              {
                name:     'Edit Organization'
                class:    'glyphicon glyphicon-edit'
                callback: editOrganization
              },
            ]
            callback: showOrganization
          }

      new App.Sidebar(
        el:     @el.find('.tabsSidebar')
        items:  items
      )

    @ArticleView()

    if force || !@editDone
      # reset form on force reload
      if force && _.isEmpty( App.TaskManager.get(@task_key).state )
        App.TaskManager.update( @task_key, { 'state': {} })
      @editDone = true

      # rerender widget if it hasn't changed
      if !@editWidget || _.isEmpty( App.TaskManager.get(@task_key).state )
        @editWidget = @Edit()

    # scroll to article if given
    if @article_id && document.getElementById( 'article-' + @article_id )
      offset = document.getElementById( 'article-' + @article_id ).offsetTop
      offset = offset - 45
      scrollTo = ->
        @scrollTo( 0, offset )
      @delay( scrollTo, 100, false )

    # enable user popups
    @userPopups()

    @autosaveStart()

  TicketTitle: =>
    # show ticket title
    new TicketTitle(
      ticket: @ticket
      el:     @el.find('.ticket-title')
    )

  ArticleView: =>
    # show article
    new ArticleView(
      ticket:             @ticket
      ticket_article_ids: @ticket_article_ids
      el:                 @el.find('.ticket-article')
      ui:                 @
    )

  Edit: =>
    # show edit
    new Edit(
      ticket:     @ticket
      el:         @el.find('.ticket-edit')
      #el:         @el.find('.edit')
      form_meta:  @form_meta
      task_key:   @task_key
      ui:         @
    )

  autosaveStop: =>
    @autosaveLast = {}
    @clearInterval( 'autosave' )

  autosaveStart: =>
    if !@autosaveLast
      @autosaveLast = App.TaskManager.get(@task_key).state || {}
    update = =>
      currentStore  = @ticket.attributes()
      currentParams = @formParam( @el.find('.edit') )

      # get diff of model
      modelDiff = @getDiff( currentStore, currentParams )
      #console.log('modelDiff', modelDiff)

      # get diff of last save
      changedBetweenLastSave = _.isEqual(currentParams, @autosaveLast )
      #console.log('changedBetweenLastSave', changedBetweenLastSave)
      if !changedBetweenLastSave
        #console.log('autosave DIFF result', changedBetweenLastSave)
        console.log('model DIFF ', modelDiff)

        @autosaveLast = clone(currentParams)
        @markFormDiff( modelDiff )

        App.TaskManager.update( @task_key, { 'state': modelDiff })
    @interval( update, 3000, 'autosave' )

  getDiff: (model, params) =>

    # do type convertation to compare it against form
    modelClone = clone(model)
    for key, value of modelClone
      if key is 'owner_id' && modelClone[key] is 1
        modelClone[key] = ''
      else if typeof value is 'number'
        modelClone[key] = value.toString()
    #console.log('LLL', modelClone)
    result = difference( modelClone, params )

  markFormDiff: (diff = {}) =>
    form = @$('.edit')

    params = @formParam( form )
    #console.log('markFormDiff', diff, params)

    # clear all changes
    if _.isEmpty(diff)
      form.removeClass('form-changed')
      form.find('.form-group').removeClass('is-changed')
      form.find('.js-reset').addClass('hide')

    # set changes
    else
      form.addClass('form-changed')
      for currentKey, currentValue of params
        element = @$('.edit [name="' + currentKey + '"]').parents('.form-group')
        if diff[currentKey]
          if !element.hasClass('is-changed')
            element.addClass('is-changed')
        else
          if element.hasClass('is-changed')
            element.removeClass('is-changed')

      form.find('.js-reset').removeClass('hide')


  submit: (e) =>
    e.stopPropagation()
    e.preventDefault()
    ticketParams = @formParam( @$('.edit') )
    console.log "submit ticket", ticketParams

    # validate ticket
    ticket = App.Ticket.fullLocal( @ticket.id )

    # update ticket attributes
    for key, value of ticketParams
      ticket[key] = value

    # set defaults
    if !@isRole('Customer')
      if !ticket['owner_id']
        ticket['owner_id'] = 1

    # check if title exists
    if !ticket['title']
      alert( App.i18n.translateContent('Title needed') )
      return

    # submit ticket & article
    @log 'notice', 'update ticket', ticket

    # disable form
    @formDisable(e)

    # validate ticket
    errors = ticket.validate(
      screen: 'edit'
    )
    if errors
      @log 'error', 'update', errors
      @formValidate(
        form:   @$('.edit')
        errors: errors
        screen: 'edit'
      )
      @formEnable(e)
      #@autosaveStart()
      return

    console.log('ticket validateion ok')

    @formEnable(e)

    # validate article
    articleParams = @formParam( @$('.article-add') )
    console.log "submit article", articleParams
    articleAttributes = App.TicketArticle.attributesGet( 'edit' )
    if articleParams['body'] || ( articleAttributes['body'] && articleAttributes['body']['null'] is false )
      articleParams.from      = @Session.get().displayName()
      articleParams.ticket_id = ticket.id
      articleParams.form_id   = @form_id

      if !articleParams['internal']
        articleParams['internal'] = false

      if @isRole('Customer')
        sender            = App.TicketArticleSender.findByAttribute( 'name', 'Customer' )
        type              = App.TicketArticleType.findByAttribute( 'name', 'web' )
        articleParams.type_id    = type.id
        articleParams.sender_id  = sender.id
      else
        sender            = App.TicketArticleSender.findByAttribute( 'name', 'Agent' )
        articleParams.sender_id  = sender.id
        type              = App.TicketArticleType.findByAttribute( 'name', articleParams['type'] )
        articleParams.type_id  = type.id

      article = new App.TicketArticle
      for key, value of articleParams
        article[key] = value

      # validate email params
      if type.name is 'email'

        # check if recipient exists
        if !articleParams['to'] && !articleParams['cc']
          alert( App.i18n.translateContent('Need recipient in "To" or "Cc".') )
          return

        # check if message exists
        if !articleParams['body']
          alert( App.i18n.translateContent('Text needed') )
          return

      # check attachment
      if articleParams['body']
        attachmentTranslated = App.i18n.translateContent('Attachment')
        attachmentTranslatedRegExp = new RegExp( attachmentTranslated, 'i' )
        if articleParams['body'].match(/attachment/i) || articleParams['body'].match( attachmentTranslatedRegExp )
          if !confirm( App.i18n.translateContent('You use attachment in text but no attachment is attached. Do you want to continue?') )
            #@autosaveStart()
            return

      console.log "article load", articleParams
      #return
      article.load(articleParams)
      errors = article.validate()
      if errors
        @log 'error', 'update article', errors
        @formValidate(
          form:   @$('.article-add')
          errors: errors
          screen: 'edit'
        )
        @formEnable(e)
        @autosaveStart()
        return

      ticket.article = article
      console.log('ARR', article)
    #return
    # submit changes
    ticket.save(
      done: (r) =>

        # reset form after save
        App.TaskManager.update( @task_key, { 'state': {} })

        @fetch( ticket.id, true )
    )

class TicketTitle extends App.Controller
  events:
    'blur .ticket-title-update': 'update'

  constructor: ->
    super

    @ticket      = App.Ticket.fullLocal( @ticket.id )
    @subscribeId = @ticket.subscribe(@render)
    @render(@ticket)

  render: (ticket) =>
    @html App.view('ticket_zoom/title')(
      ticket:     ticket
      isCustomer: @isRole('Customer')
    )

    @$('.ticket-title-update').ce({
      mode:      'textonly'
      multiline: false
      maxlength: 250
    })

    # show frontend times
    @frontendTimeUpdate()

  update: (e) =>
    title = $(e.target).ceg({ mode: 'textonly' }) || '-'

    # update title
    if title isnt @ticket.title
      @ticket.title = title
      @ticket.save()

      # update taskbar with new meta data
      App.Event.trigger 'task:render'

  release: =>
    App.Ticket.unsubscribe( @subscribeId )
    #if @subscribeIdEdit
    App.Ticket.unsubscribe( @subscribeIdEdit )

class Edit extends App.Controller
  elements:
    'textarea' :                    'textarea'
    '.edit-control-item' :          'editControlItem'
    '.edit-controls':               'editControls'
    '.recipient-picker':            'recipientPicker'
    '.recipient-list':              'recipientList'
    '.recipient-list .list-arrow':  'recipientListArrow'
    '.js-attachment':               'attachmentHolder'
    '.js-attachment-text':          'attachmentText'
    '.bubble-placeholder-hint':     'bubblePlaceholderHint'

  events:
    'click .submit':             'update'
    'click [data-type="reset"]': 'reset'
    'click .visibility-toggle':  'toggle_visibility'
    'click .pop-selectable':     'selectArticleType'
    'click .pop-selected':       'showSelectableArticleType'
    'focus textarea':            'open_textarea'
    'input textarea':            'detect_empty_textarea'
    'click .recipient-picker':   'toggle_recipients'
    'click .recipient-list':     'stopPropagation'
    'click .list-entry-type div':  'change_type'
    'submit .recipient-list form': 'add_recipient'

  constructor: ->
    super

    @textareaHeight =
      open: 148
      closed: 38

    @render()

  stopPropagation: (e) ->
    e.stopPropagation()

  release: =>
    #@autosaveStop()
    if @subscribeIdTextModule
      App.Ticket.unsubscribe(@subscribeIdTextModule)

  render: ->

    ticket = App.Ticket.fullLocal( @ticket.id )

    # gets referenced in @setArticleType
    @type = 'note'
    articleTypes = [
      {
        name: 'note'
        icon: 'note'
      },
      {
        name: 'email'
        icon: 'email'
      },
      {
        name: 'facebook'
        icon: 'facebook'
      },
      {
        name: 'twitter'
        icon: 'twitter'
      },
      {
        name: 'phone'
        icon: 'phone'
      },
    ]
    if @isRole('Customer')
      @type = 'note'
      articleTypes = [
        {
          name: 'note'
          icon: 'note'
        },
      ]

    @html App.view('ticket_zoom/edit')(
      ticket:       ticket
      type:         @type
      articleTypes: articleTypes
      isCustomer:   @isRole('Customer')
    )

    @form_id = App.ControllerForm.formId()
    defaults = ticket.attributes()
    if @isRole('Customer')
      delete defaults['state_id']
      delete defaults['state']
    if !_.isEmpty( App.TaskManager.get(@task_key).state )
      defaults = App.TaskManager.get(@task_key).state

    new App.ControllerForm(
      el:        @el.find('.form-article-update')
      form_id:   @form_id
      model:     App.TicketArticle
      screen:   'edit'
      filter:
        type_id: [1,9,5]
      params:    defaults
      dependency: [
        {
          bind: {
            name:     'type_id'
            relation: 'TicketArticleType'
            value:    ['email']
          },
          change: {
            action: 'show'
            name: ['to', 'cc'],
          },
        },
        {
          bind: {
            name:     'type_id'
            relation: 'TicketArticleType'
            value:    ['note', 'phone', 'twitter status']
          },
          change: {
            action: 'hide'
            name: ['to', 'cc'],
          },
        },
        {
          bind: {
            name:     'type_id'
            relation: 'TicketArticleType'
            value:    ['twitter direct-message']
          },
          change: {
            action: 'show'
            name: ['to'],
          },
        },
      ]
    )

    # start auto save
    #@autosaveStart()

    # show text module UI
    if !@isRole('Customer')
      textModule = new App.WidgetTextModule(
        el:   @textarea
        data:
          ticket: ticket
      )
      callback = (ticket) =>
        textModule.reload(
          ticket: ticket
        )
      @subscribeIdTextModule = ticket.subscribe( callback )

  toggle_recipients: =>
    if !@pickRecipientsCatcher
      @show_recipients()
    else
      @hide_recipients()

  show_recipients: ->
    padding = 15

    @recipientPicker.addClass('is-open')
    @recipientList.removeClass('hide')

    pickerDimensions = @recipientPicker.get(0).getBoundingClientRect()
    availableHeight = @recipientPicker.scrollParent().outerHeight()

    top = pickerDimensions.height/2 - @recipientList.height()/2
    bottomDistance = availableHeight - padding - (pickerDimensions.top + top + @recipientList.height())

    if bottomDistance < 0
      top += bottomDistance

    arrowCenter = -top + pickerDimensions.height/2

    @recipientListArrow.css('top', arrowCenter)
    @recipientList.css('top', top)

    $.Velocity.hook(@recipientList, 'transformOriginX', "0")
    $.Velocity.hook(@recipientList, 'transformOriginY', "#{ arrowCenter }px")

    @recipientList.velocity
      properties:
        scale: [ 1, 0 ]
        opacity: [ 1, 0 ]
      options:
        speed: 300
        easing: [ 0.34, 1.61, 0.7, 1 ]

    @pickRecipientsCatcher = new App.clickCatcher
      holder: @el.offsetParent()
      callback: @hide_recipients
      zIndexScale: 6

  hide_recipients: =>
    @pickRecipientsCatcher.remove()
    @pickRecipientsCatcher = null

    @recipientPicker.removeClass('is-open')

    @recipientList.velocity
      properties:
        scale: [ 0, 1 ]
        opacity: [ 0, 1 ]
      options:
        speed: 300
        easing: [ 500, 20 ]
        complete: -> @recipientList.addClass('hide')

  change_type: (e) ->
    $(e.target).addClass('active').siblings('.active').removeClass('active')
    # store $(this).data('value')

  add_recipient: (e) ->
    e.stopPropagation()
    e.preventDefault()
    console.log "add recipient", e
    # store recipient 

  toggle_visibility: ->
    if @el.hasClass('is-public')
      @el.removeClass('is-public')
      @el.addClass('is-internal')
    else
      @el.addClass('is-public')
      @el.removeClass('is-internal')

  showSelectableArticleType: =>
    @el.find('.pop-selector').removeClass('hide')

    @selectTypeCatcher = new App.clickCatcher
      holder: @el.offsetParent()
      callback: @hideSelectableArticleType
      zIndexScale: 6

  selectArticleType: (e) =>
    @setArticleType $(e.target).data('value')
    @hideSelectableArticleType()
    @selectTypeCatcher.remove()
    @selectTypeCatcher = null

  hideSelectableArticleType: =>
    @el.find('.pop-selector').addClass('hide')

  setArticleType: (type) ->
    typeIcon = @el.find('.pop-selected .icon')
    if @type
      typeIcon.removeClass @type
    @type = type
    typeIcon.addClass @type

  detect_empty_textarea: =>
    if !@textarea.val()
      @add_textarea_catcher()
    else
      @remove_textarea_catcher()

  open_textarea: =>
    if !@textareaCatcher and !@textarea.val()
      @el.addClass('is-open')

      @textarea.velocity
        properties:
          height: "#{ @textareaHeight.open - 38 }px"
          marginBottom: 38
        options:
          duration: 300
          easing: 'easeOutQuad'

      # scroll to bottom
      @textarea.velocity "scroll",
        container: @textarea.scrollParent()
        offset: 99999
        duration: 300
        easing: 'easeOutQuad'
        queue: false

      @editControlItem.velocity "transition.slideRightIn",
        duration: 300
        stagger: 50
        drag: true

      # move attachment text to the left bottom (bottom happens automatically)

      @attachmentHolder.velocity
        properties:
          translateX: -@attachmentText.position().left + "px"
        options:
          duration: 300
          easing: 'easeOutQuad'

      @bubblePlaceholderHint.velocity
        properties:
          opacity: 0
        options:
          duration: 300

      @add_textarea_catcher()

  add_textarea_catcher: ->
    @textareaCatcher = new App.clickCatcher
      holder: @el.offsetParent()
      callback: @close_textarea
      zIndexScale: 4

  remove_textarea_catcher: ->
    return if !@textareaCatcher
    @textareaCatcher.remove()
    @textareaCatcher = null

  close_textarea: =>
    @remove_textarea_catcher()
    if !@textarea.val()

      @textarea.velocity
        properties:
          height: "#{ @textareaHeight.closed }px"
          marginBottom: 0
        options:
          duration: 300
          easing: 'easeOutQuad'
          complete: => @el.removeClass('is-open')

      @attachmentHolder.velocity
        properties:
          translateX: 0
        options:
          duration: 300
          easing: 'easeOutQuad'

      @bubblePlaceholderHint.velocity
        properties:
          opacity: 1
        options:
          duration: 300

      @editControlItem.css('display', 'none')

  autosaveStop: =>
    @clearInterval( 'autosave' )

  autosaveStart: =>
    @autosaveLast = _.clone( @ui.formDefault )
    update = =>
      currentData = @formParam( @el.find('.ticket-update') )
      diff = difference( @autosaveLast, currentData )
      if !@autosaveLast || ( diff && !_.isEmpty( diff ) )
        @autosaveLast = currentData
        @log 'notice', 'form hash changed', diff, currentData
        @el.find('.edit').addClass('form-changed')
        @el.find('.edit').find('.reset-message').show()
        @el.find('.edit').find('.reset-message').removeClass('hide')
        App.TaskManager.update( @task_key, { 'state': currentData })
    @interval( update, 3000, 'autosave' )

  update: (e) =>
    e.preventDefault()
    #@autosaveStop()
    params = @formParam(e.target)

    # get ticket
    ticket = App.Ticket.fullLocal( @ticket.id )

    @log 'notice', 'update', params, ticket

    # update local ticket

    # create local article


    # find sender_id
    if @isRole('Customer')
      sender            = App.TicketArticleSender.findByAttribute( 'name', 'Customer' )
      type              = App.TicketArticleType.findByAttribute( 'name', 'web' )
      params.type_id    = type.id
      params.sender_id  = sender.id
    else
      sender            = App.TicketArticleSender.findByAttribute( 'name', 'Agent' )
      type              = App.TicketArticleType.find( params['type_id'] )
      params.sender_id  = sender.id

    # update ticket
    for key, value of params
      ticket[key] = value

    # check owner assignment
    if !@isRole('Customer')
      if !ticket['owner_id']
        ticket['owner_id'] = 1

    # check if title exists
    if !ticket['title']
      alert( App.i18n.translateContent('Title needed') )
      return

    # validate email params
    if type.name is 'email'

      # check if recipient exists
      if !params['to'] && !params['cc']
        alert( App.i18n.translateContent('Need recipient in "To" or "Cc".') )
        return

      # check if message exists
      if !params['body']
        alert( App.i18n.translateContent('Text needed') )
        return

    # check attachment
    if params['body']
      attachmentTranslated = App.i18n.translateContent('Attachment')
      attachmentTranslatedRegExp = new RegExp( attachmentTranslated, 'i' )
      if params['body'].match(/attachment/i) || params['body'].match( attachmentTranslatedRegExp )
        if !confirm( App.i18n.translateContent('You use attachment in text but no attachment is attached. Do you want to continue?') )
          #@autosaveStart()
          return

    # submit ticket & article
    @log 'notice', 'update ticket', ticket

    # disable form
    @formDisable(e)

    # validate ticket
    errors = ticket.validate(
      screen: 'edit'
    )
    if errors
      @log 'error', 'update', errors

      @log 'error', errors
      @formValidate(
        form:   e.target
        errors: errors
        screen: 'edit'
      )
      @formEnable(e)
      #@autosaveStart()
      return

    # validate article
    articleAttributes = App.TicketArticle.attributesGet( 'edit' )
    if params['body'] || ( articleAttributes['body'] && articleAttributes['body']['null'] is false )
      article = new App.TicketArticle
      params.from      = @Session.get().displayName()
      params.ticket_id = ticket.id
      params.form_id   = @form_id

      if !params['internal']
        params['internal'] = false

      @log 'notice', 'update article', params, sender
      article.load(params)
      errors = article.validate()
      if errors
        @log 'error', 'update article', errors
        @formValidate(
          form:   e.target
          errors: errors
          screen: 'edit'
        )
        @formEnable(e)
        @autosaveStart()
        return

    ticket.article = article
    ticket.save(
      done: (r) =>

        # reset form after save
        App.TaskManager.update( @task_key, { 'state': {} })

        @ui.fetch( ticket.id, true )
    )

  reset: (e) =>
    e.preventDefault()
    App.TaskManager.update( @task_key, { 'state': {} })
    @render()


class ArticleView extends App.Controller
  events:
    'click [data-type=public]':     'public_internal'
    'click [data-type=internal]':   'public_internal'
    'click .show_toogle':           'show_toogle'
    'click [data-type=reply]':      'reply'
    'click .text-bubble':           'toggle_meta'
    'click .text-bubble a':         'stopPropagation'
#    'click [data-type=reply-all]':  'replyall'

  constructor: ->
    super
    @render()

  render: ->

    # get all articles
    @articles = []
    for article_id in @ticket_article_ids
      article = App.TicketArticle.fullLocal( article_id )
      @articles.push article

    # rework articles
    for article in @articles
      new Article( article: article )

    @html App.view('ticket_zoom/article_view')(
      ticket:     @ticket
      articles:   @articles
      isCustomer: @isRole('Customer')
    )

    # show frontend times
    @frontendTimeUpdate()

    # enable user popups
    @userPopups()

  public_internal: (e) ->
    e.preventDefault()
    article_id = $(e.target).parents('[data-id]').data('id')

    # storage update
    article = App.TicketArticle.find(article_id)
    internal = true
    if article.internal == true
      internal = false
    article.updateAttributes(
      internal: internal
    )

    # runntime update
    if internal
      $(e.target).closest('.ticket-article-item').addClass('is-internal')
    else
      $(e.target).closest('.ticket-article-item').removeClass('is-internal')

  show_toogle: (e) ->
    e.stopPropagation()
    e.preventDefault()
    #$(e.target).hide()
    if $(e.target).next('div')[0]
      if $(e.target).next('div').hasClass('hide')
        $(e.target).next('div').removeClass('hide')
        $(e.target).text( App.i18n.translateContent('Fold in') )
      else
        $(e.target).text( App.i18n.translateContent('See more') )
        $(e.target).next('div').addClass('hide')

  stopPropagation: (e) ->
    e.stopPropagation()

  toggle_meta: (e) ->
    e.preventDefault()

    animSpeed = 300
    article = $(e.target).closest('.ticket-article-item')
    metaTopClip = article.find('.article-meta-clip.top')
    metaBottomClip = article.find('.article-meta-clip.bottom')
    metaTop = article.find('.article-content-meta.top')
    metaBottom = article.find('.article-content-meta.bottom')

    if @elementContainsSelection( article.get(0) )
      @stopPropagation(e)
      return false

    if !metaTop.hasClass('hide')
      article.removeClass('state--folde-out')

      # scroll back up
      article.velocity "scroll",
        container: article.scrollParent()
        offset: -article.offset().top - metaTop.outerHeight()
        duration: animSpeed
        easing: 'easeOutQuad'

      metaTop.velocity
        properties:
          translateY: 0
          opacity: [ 0, 1 ]
        options:
          speed: animSpeed
          easing: 'easeOutQuad'
          complete: -> metaTop.addClass('hide')

      metaBottom.velocity
        properties:
          translateY: [ -metaBottom.outerHeight(), 0 ]
          opacity: [ 0, 1 ]
        options:
          speed: animSpeed
          easing: 'easeOutQuad'
          complete: -> metaBottom.addClass('hide')

      metaTopClip.velocity({ height: 0 }, animSpeed, 'easeOutQuad')
      metaBottomClip.velocity({ height: 0 }, animSpeed, 'easeOutQuad')
    else
      article.addClass('state--folde-out')
      metaBottom.removeClass('hide')
      metaTop.removeClass('hide')

      # balance out the top meta height by scrolling down
      article.velocity("scroll", 
        container: article.scrollParent()
        offset: -article.offset().top + metaTop.outerHeight()
        duration: animSpeed
        easing: 'easeOutQuad'
      )

      metaTop.velocity
        properties:
          translateY: [ 0, metaTop.outerHeight() ]
          opacity: [ 1, 0 ]
        options:
          speed: animSpeed
          easing: 'easeOutQuad'

      metaBottom.velocity
        properties:
          translateY: [ 0, -metaBottom.outerHeight() ]
          opacity: [ 1, 0 ]
        options:
          speed: animSpeed
          easing: 'easeOutQuad'

      metaTopClip.velocity({ height: metaTop.outerHeight() }, animSpeed, 'easeOutQuad')
      metaBottomClip.velocity({ height: metaBottom.outerHeight() }, animSpeed, 'easeOutQuad')

  isOrContains: (node, container) ->
    while node
      if node is container
        return true
      node = node.parentNode
    false

  elementContainsSelection: (el) ->
    sel = window.getSelection()
    if sel.rangeCount > 0 && sel.toString()
      for i in [0..sel.rangeCount-1]
        if !@isOrContains(sel.getRangeAt(i).commonAncestorContainer, el)
          return false
      return true
    false

  checkIfSignatureIsNeeded: (type) =>

    # add signature
    if @ui.signature && @ui.signature.body && type.name is 'email'
      body   = @ui.el.find('[name="body"]').val() || ''
      regexp = new RegExp( escapeRegExp( @ui.signature.body ) , 'i')
      if !body.match(regexp)
        body = body + "\n" + @ui.signature.body
        @ui.el.find('[name="body"]').val( body )

        # update textarea size
        @ui.el.find('[name="body"]').trigger('change')

  reply: (e) =>
    e.preventDefault()
    article_id   = $(e.target).parents('[data-id]').data('id')
    article      = App.TicketArticle.find( article_id )
    type         = App.TicketArticleType.find( article.type_id )
    customer     = App.User.find( article.created_by_id )

    # update form
    @checkIfSignatureIsNeeded(type)

    # preselect article type
    @ui.el.find('[name="type_id"]').find('option:selected').removeAttr('selected')
    @ui.el.find('[name="type_id"]').find('[value="' + type.id + '"]').attr('selected',true)
    @ui.el.find('[name="type_id"]').trigger('change')

    # empty form
    #@ui.el.find('[name="to"]').val('')
    #@ui.el.find('[name="cc"]').val('')
    #@ui.el.find('[name="subject"]').val('')
    @ui.el.find('[name="in_reply_to"]').val('')

    if article.message_id
      @ui.el.find('[name="in_reply_to"]').val(article.message_id)

    if type.name is 'twitter status'

      # set to in body
      to = customer.accounts['twitter'].username || customer.accounts['twitter'].uid
      @ui.el.find('[name="body"]').val('@' + to)

    else if type.name is 'twitter direct-message'

      # show to
      to = customer.accounts['twitter'].username || customer.accounts['twitter'].uid
      @ui.el.find('[name="to"]').val(to)

    else if type.name is 'email'
      @ui.el.find('[name="to"]').val(article.from)

    # add quoted text if needed
    selectedText = App.ClipBoard.getSelected()
    if selectedText
      body = @ui.el.find('[name="body"]').val() || ''
      selectedText = selectedText.replace /^(.*)$/mg, (match) =>
        '> ' + match
      body = selectedText + "\n" + body
      @ui.el.find('[name="body"]').val(body)

      # update textarea size
      @ui.el.find('[name="body"]').trigger('change')

class Article extends App.Controller
  constructor: ->
    super

    # define actions
    @actionRow()

    # check attachments
    @attachments()

    # html rework
    @preview()

  preview: ->

    # build html body
    # cleanup body
#    @article['html'] = @article.body.trim()
    @article['html'] = $.trim( @article.body )
    @article['html'].replace( /\n\r/g, "\n" )
    @article['html'].replace( /\n\n\n/g, "\n\n" )

    # if body has more then x lines / else search for signature
    preview       = 10
    preview_mode  = false
    article_lines = @article['html'].split(/\n/)
    if article_lines.length > preview
      preview_mode = true
      if article_lines[preview] is ''
        article_lines.splice( preview, 0, '-----SEEMORE-----' )
      else
        article_lines.splice( preview - 1, 0, '-----SEEMORE-----' )
      @article['html'] = article_lines.join("\n")
    @article['html'] = window.linkify( @article['html'] )
    notify = '<a href="#" class="show_toogle">' + App.i18n.translateContent('See more') + '</a>'

    # preview mode
    if preview_mode
      @article_changed = false
      @article['html'] = @article['html'].replace /^-----SEEMORE-----\n/m, (match) =>
        @article_changed = true
        notify + '<div class="hide preview">'
      if @article_changed
        @article['html'] = @article['html'] + '</div>'

    # hide signatures and so on
    else
      @article_changed = false
      @article['html'] = @article['html'].replace /^\n{0,10}(--|__)/m, (match) =>
        @article_changed = true
        notify + '<div class="hide preview">' + match
      if @article_changed
        @article['html'] = @article['html'] + '</div>'

  actionRow: ->
    if @isRole('Customer')
      @article.actions = []
      return

    actions = []
    if @article.internal is true
      actions = [
        {
          name: 'set to public'
          type: 'public'
        }
      ]
    else
      actions = [
        {
          name: 'set to internal'
          type: 'internal'
        }
      ]
    if @article.type.name is 'note'
#        actions.push []
    else
      if @article.sender.name is 'Customer'
        actions.push {
          name: 'reply'
          type: 'reply'
          href: '#'
        }
#        actions.push {
#          name: 'reply all'
#          type: 'reply-all'
#          href: '#'
#        }
        actions.push {
          name: 'split'
          type: 'split'
          href: '#ticket/create/' + @article.ticket_id + '/' + @article.id
        }
    @article.actions = actions

  attachments: ->
    if @article.attachments
      for attachment in @article.attachments
        attachment.size = @humanFileSize(attachment.size)

class TicketZoomRouter extends App.ControllerPermanent
  constructor: (params) ->
    super

    # cleanup params
    clean_params =
      ticket_id:  params.ticket_id
      article_id: params.article_id
      nav:        params.nav

    App.TaskManager.add( 'Ticket-' + @ticket_id, 'TicketZoom', clean_params )

App.Config.set( 'ticket/zoom/:ticket_id', TicketZoomRouter, 'Routes' )
App.Config.set( 'ticket/zoom/:ticket_id/nav/:nav', TicketZoomRouter, 'Routes' )
App.Config.set( 'ticket/zoom/:ticket_id/:article_id', TicketZoomRouter, 'Routes' )
