class PaymentWorkflow extends FormWorkflow

  constructor: (options = {}, data) ->
    unless options.confirmForm
      throw new Error "You must provide a confirmForm option!"

    super options, data

    @aggregatedData = {}

  preparePaymentMethods: (formData) ->
    @setState 'choice'

    paymentController = KD.getSingleton 'paymentController'

    choiceForm = @getForm 'choice'

    paymentField = choiceForm.fields['Payment method']

    paymentController.fetchPaymentMethods (err, paymentMethods) =>
      return if KD.showError err

      { preferredPaymentMethod, methods, appStorage } = paymentMethods

      switch methods.length

        when 0 then @setState 'entry'

        when 1 then do ([method] = methods) =>

          paymentField.addSubView new PaymentMethodView {}, method
          choiceForm.addCustomData 'paymentMethod', method

        else

          methodsByPaymentMethodId =
            methods.reduce( (acc, method) ->
              acc[method.paymentMethodId] = method
              acc
            , {})

          defaultPaymentMethod = preferredPaymentMethod ? methods[0].paymentMethodId

          defaultMethod = methodsByPaymentMethodId[defaultPaymentMethod]

          choiceForm.addCustomData 'paymentMethod', defaultMethod

          select = new KDSelectBox
            defaultValue  : defaultPaymentMethod
            name          : 'paymentMethodId'
            selectOptions : methods.map (method) ->
              title       : KD.utils.getPaymentMethodTitle method
              value       : method.paymentMethodId
            callback      : (paymentMethodId) ->
              chosenMethod = methodsByPaymentMethodId[paymentMethodId]
              choiceForm.addCustomData 'paymentMethod', chosenMethod

          paymentField.addSubView select

  addAggregateData: (formData) ->
    for own key, val of formData
      if @aggregatedData[key]?
        console.warn "Duplicate form data property: #{key}"
      @aggregatedData[key] = val

  selectPaymentMethod: (method) ->
    { paymentMethodId } = method
    @addAggregateData { paymentMethodId }
    (@getForm 'confirm').setPaymentMethod? method
    @setState 'confirm'

  createChoiceForm: ->

    form = new PaymentChoiceForm

    form.on 'PaymentMethodChosen', (method) =>
      @selectPaymentMethod method

    form.on 'PaymentMethodNotChosen', =>
      @setState 'entry'

    return form

  createEntryForm: ->

    form = new PaymentForm

    paymentController = KD.getSingleton 'paymentController'

    paymentController.observePaymentSave form, (err, method) =>
      return if KD.showError err

      @selectPaymentMethod method

    return form

  setState: (state) ->
    @showForm state
    if state is 'confirm'
      confirmData = @utils.extend {}, @aggregatedData
      (@getForm 'confirm').setData confirmData

  viewAppended:-> @prepareWorkflow()

  prepareWorkflow: ->

    @requireData [
      'productData'

      @any('paymentMethod', 'subscription')
      
      'userConfirmation'
    ]
    # "product form" can be used for collecting some product-related data
    # before the payment method collection/selection process begins.  If you
    # use this feature, make sure to emit the "DataCollected" event with any
    # data that you want aggregated (that you want to be able to access from
    # the "PaymentConfirmed" listeners).
    { productForm } = @getOptions()

    if productForm?
      @addForm 'product', productForm, ['productData', 'subscription']
      productForm.on 'DataCollected', (productData) =>
        @addAggregateData { productData }
        @preparePaymentMethods()

    # "choice form" is for choosing from existing payment methods on-file.
    @addForm 'choice', @createChoiceForm(), ['paymentMethod']

    # "entry form" is for entering a new payment method for us to file.
    @addForm 'entry', @createEntryForm(), ['paymentMethod']

    # "confirm form" is required.  This form should render a summary, and emit
    # a "PaymentConfirmed" after user approval.
    { confirmForm } = @getOptions()
    @addForm 'confirm', confirmForm, ['userConfirmation']

    confirmForm.on 'PaymentConfirmed', =>
      # You should listen to the "PaymentConfirmed" event from outside the
      # workflow.  We'll forward a result like:
      #   { paymentMethodId, productData* }
      # * "productData" is the data that you emitted from the product form.
      @emit 'PaymentConfirmed', @aggregatedData

    # if provided, show the product form, otherwise skip to payment methods.
    if productForm?
    then @setState 'product'
    else @preparePaymentMethods()

    return this