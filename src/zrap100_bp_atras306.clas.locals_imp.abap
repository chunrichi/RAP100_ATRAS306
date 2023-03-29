CLASS lhc_atras306 DEFINITION INHERITING FROM cl_abap_behavior_handler.
  PRIVATE SECTION.
    METHODS:
      get_global_authorizations FOR GLOBAL AUTHORIZATION
        IMPORTING
        REQUEST requested_authorizations FOR atras306
        RESULT result,
      earlynumbering_create FOR NUMBERING
        IMPORTING entities FOR CREATE atras306,
      setstatustoopen FOR DETERMINE ON MODIFY
        IMPORTING keys FOR atras306~setstatustoopen,
      validationcustomer FOR VALIDATE ON SAVE
        IMPORTING keys FOR atras306~validationcustomer.

    METHODS validationdates FOR VALIDATE ON SAVE
      IMPORTING keys FOR atras306~validationdates.
    METHODS deductDiscount FOR MODIFY
      IMPORTING keys FOR ACTION atras306~deductDiscount RESULT result.
    METHODS copyTravel FOR MODIFY
      IMPORTING keys FOR ACTION atras306~copyTravel.
    METHODS acceptTravel FOR MODIFY
      IMPORTING keys FOR ACTION atras306~acceptTravel RESULT result.

    METHODS rejectTravel FOR MODIFY
      IMPORTING keys FOR ACTION atras306~rejectTravel RESULT result.
    METHODS get_instance_features FOR INSTANCE FEATURES
      IMPORTING keys REQUEST requested_features FOR atras306 RESULT result.
ENDCLASS.

CLASS lhc_atras306 IMPLEMENTATION.
  METHOD get_global_authorizations.
  ENDMETHOD.
  METHOD earlynumbering_create.
    " 选中方法后点击 F2 可查看具体更改参数

    " 早期编号

    DATA:
      entity           TYPE STRUCTURE FOR CREATE zrap100_r_atras306,
      travel_id_max    TYPE /dmo/travel_id,
      " change to abap_false if you get the ABAP Runtime error 'BEHAVIOR_ILLEGAL_STATEMENT'
      use_number_range TYPE abap_bool VALUE abap_false.

    "Ensure Travel ID is not set yet (idempotent)- must be checked when BO is draft-enabled
    LOOP AT entities INTO entity WHERE TravelID IS NOT INITIAL.
      APPEND CORRESPONDING #( entity ) TO mapped-atras306.
    ENDLOOP.

    DATA(entities_wo_travelid) = entities.
    "Remove the entries with an existing Travel ID
    DELETE entities_wo_travelid WHERE TravelID IS NOT INITIAL.

    IF use_number_range = abap_true.
      "Get numbers
      TRY.
          cl_numberrange_runtime=>number_get(
            EXPORTING
              nr_range_nr       = '01'
              object            = '/DMO/TRV_M'
              quantity          = CONV #( lines( entities_wo_travelid ) )
            IMPORTING
              number            = DATA(number_range_key)
              returncode        = DATA(number_range_return_code)
              returned_quantity = DATA(number_range_returned_quantity)
          ).
        CATCH cx_number_ranges INTO DATA(lx_number_ranges).
          LOOP AT entities_wo_travelid INTO entity.
            APPEND VALUE #(  %cid      = entity-%cid
                             %key      = entity-%key
                             %is_draft = entity-%is_draft
                             %msg      = lx_number_ranges
                          ) TO reported-atras306.
            APPEND VALUE #(  %cid      = entity-%cid
                             %key      = entity-%key
                             %is_draft = entity-%is_draft
                          ) TO failed-atras306.
          ENDLOOP.
          EXIT.
      ENDTRY.

      "determine the first free travel ID from the number range
      travel_id_max = number_range_key - number_range_returned_quantity.
    ELSE.
      "determine the first free travel ID without number range
      "Get max travel ID from active table
      SELECT SINGLE FROM zrap100_atraS306 FIELDS MAX( travel_id ) AS travelID INTO @travel_id_max.
      "Get max travel ID from draft table
      SELECT SINGLE FROM zrap100_dtraS306 FIELDS MAX( travelid ) INTO @DATA(max_travelid_draft).
      IF max_travelid_draft > travel_id_max.
        travel_id_max = max_travelid_draft.
      ENDIF.
    ENDIF.

    "Set Travel ID for new instances w/o ID
    LOOP AT entities_wo_travelid INTO entity.
      travel_id_max += 1.
      entity-TravelID = travel_id_max.

      APPEND VALUE #( %cid      = entity-%cid
                      %key      = entity-%key
                      %is_draft = entity-%is_draft
                    ) TO mapped-atras306.
    ENDLOOP.
  ENDMETHOD.

  METHOD setStatusToOpen.
    " 保存时触发（创建）

    CONSTANTS:
      BEGIN OF travel_status,
        open     TYPE c LENGTH 1 VALUE 'O', "Open
        accepted TYPE c LENGTH 1 VALUE 'A', "Accepted
        rejected TYPE c LENGTH 1 VALUE 'X', "Rejected
      END OF travel_status.

    "Read travel instances of the transferred keys
    READ ENTITIES OF zrap100_r_atras306 IN LOCAL MODE
     ENTITY atras306
       FIELDS ( OverallStatus )
       WITH CORRESPONDING #( keys )
     RESULT DATA(travels)
     FAILED DATA(read_failed).

    "If overall travel status is already set, do nothing, i.e. remove such instances
    DELETE travels WHERE OverallStatus IS NOT INITIAL.
    CHECK travels IS NOT INITIAL.

    "else set overall travel status to open ('O')
    MODIFY ENTITIES OF zrap100_r_atras306 IN LOCAL MODE
      ENTITY atras306
        UPDATE SET FIELDS
        WITH VALUE #( FOR travel IN travels ( %tky    = travel-%tky
                                              OverallStatus = travel_status-open ) )
    REPORTED DATA(update_reported).

    "Set the changing parameter
    reported = CORRESPONDING #( DEEP update_reported ).

  ENDMETHOD.

  METHOD validationCustomer.
    " 检查用户字段

    " 读取数据
    READ ENTITIES OF zrap100_r_atras306 IN LOCAL MODE
    ENTITY atras306
     FIELDS ( CustomerID )
     WITH CORRESPONDING #( keys )
    RESULT DATA(travels).

    DATA customers TYPE SORTED TABLE OF /dmo/customer WITH UNIQUE KEY customer_id.

    " 获取用户信息
    customers = CORRESPONDING #( travels DISCARDING DUPLICATES MAPPING customer_id = customerID EXCEPT * ).
    DELETE customers WHERE customer_id IS INITIAL.
    IF customers IS NOT INITIAL.
      " 检查用户id是否存在
      SELECT FROM /dmo/customer FIELDS customer_id
                                FOR ALL ENTRIES IN @customers
                                WHERE customer_id = @customers-customer_id
        INTO TABLE @DATA(valid_customers).
    ENDIF.

    " 返回报错
    LOOP AT travels INTO DATA(travel).
      APPEND VALUE #(  %tky                 = travel-%tky
                       %state_area          = 'VALIDATE_CUSTOMER'
                     ) TO reported-atras306.

      IF travel-CustomerID IS  INITIAL.
        APPEND VALUE #( %tky = travel-%tky ) TO failed-atras306.

        APPEND VALUE #( %tky                = travel-%tky
                        %state_area         = 'VALIDATE_CUSTOMER'
                        %msg                = NEW /dmo/cm_flight_messages(
                                                                textid   = /dmo/cm_flight_messages=>enter_customer_id
                                                                severity = if_abap_behv_message=>severity-error )
                        %element-CustomerID = if_abap_behv=>mk-on
                      ) TO reported-atras306.

      ELSEIF travel-CustomerID IS NOT INITIAL AND NOT line_exists( valid_customers[ customer_id = travel-CustomerID ] ).
        APPEND VALUE #(  %tky = travel-%tky ) TO failed-atras306.

        APPEND VALUE #(  %tky                = travel-%tky
                         %state_area         = 'VALIDATE_CUSTOMER'
                         %msg                = NEW /dmo/cm_flight_messages(
                                                                customer_id = travel-customerid
                                                                textid      = /dmo/cm_flight_messages=>customer_unkown
                                                                severity    = if_abap_behv_message=>severity-error )
                         %element-CustomerID = if_abap_behv=>mk-on
                      ) TO reported-atras306.
      ENDIF.

    ENDLOOP.
  ENDMETHOD.

  METHOD validationDates.
    " 检查日期字段

    " 读取数据
    READ ENTITIES OF zrap100_r_atras306 IN LOCAL MODE
      ENTITY atras306
        FIELDS (  BeginDate EndDate TravelID )
        WITH CORRESPONDING #( keys )
      RESULT DATA(travels).

    LOOP AT travels INTO DATA(travel).

      APPEND VALUE #(  %tky               = travel-%tky
                       %state_area        = 'VALIDATE_DATES' ) TO reported-atras306.

      IF travel-BeginDate IS INITIAL.
        APPEND VALUE #( %tky = travel-%tky ) TO failed-atras306.

        APPEND VALUE #( %tky               = travel-%tky
                        %state_area        = 'VALIDATE_DATES'
                         %msg              = NEW /dmo/cm_flight_messages(
                                                                textid   = /dmo/cm_flight_messages=>enter_begin_date
                                                                severity = if_abap_behv_message=>severity-error )
                      %element-BeginDate = if_abap_behv=>mk-on ) TO reported-atras306.
      ENDIF.
      IF travel-BeginDate < cl_abap_context_info=>get_system_date( ) AND travel-BeginDate IS NOT INITIAL.
        APPEND VALUE #( %tky               = travel-%tky ) TO failed-atras306.

        APPEND VALUE #( %tky               = travel-%tky
                        %state_area        = 'VALIDATE_DATES'
                         %msg              = NEW /dmo/cm_flight_messages(
                                                                begin_date = travel-BeginDate
                                                                textid     = /dmo/cm_flight_messages=>begin_date_on_or_bef_sysdate
                                                                severity   = if_abap_behv_message=>severity-error )
                        %element-BeginDate = if_abap_behv=>mk-on ) TO reported-atras306.
      ENDIF.
      IF travel-EndDate IS INITIAL.
        APPEND VALUE #( %tky = travel-%tky ) TO failed-atras306.

        APPEND VALUE #( %tky               = travel-%tky
                        %state_area        = 'VALIDATE_DATES'
                         %msg                = NEW /dmo/cm_flight_messages(
                                                                textid   = /dmo/cm_flight_messages=>enter_end_date
                                                               severity = if_abap_behv_message=>severity-error )
                        %element-EndDate   = if_abap_behv=>mk-on ) TO reported-atras306.
      ENDIF.
      IF travel-EndDate < travel-BeginDate AND travel-BeginDate IS NOT INITIAL
                                           AND travel-EndDate IS NOT INITIAL.
        APPEND VALUE #( %tky = travel-%tky ) TO failed-atras306.

        APPEND VALUE #( %tky               = travel-%tky
                        %state_area        = 'VALIDATE_DATES'
                        %msg               = NEW /dmo/cm_flight_messages(
                                                                textid     = /dmo/cm_flight_messages=>begin_date_bef_end_date
                                                                begin_date = travel-BeginDate
                                                                end_date   = travel-EndDate
                                                                severity   = if_abap_behv_message=>severity-error )
                        %element-BeginDate = if_abap_behv=>mk-on
                        %element-EndDate   = if_abap_behv=>mk-on ) TO reported-atras306.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD deductDiscount.
    " 新增action

    DATA travels_for_update TYPE TABLE FOR UPDATE zrap100_r_atras306.
    DATA(keys_with_valid_discount) = keys.

    " 检查输入参数的折扣值
    LOOP AT keys_with_valid_discount ASSIGNING FIELD-SYMBOL(<key_with_valid_discount>)
        WHERE %param-discount_percent IS INITIAL
           OR %param-discount_percent > 100
           OR %param-discount_percent <= 0.
      " 返回报错
      APPEND VALUE #( %tky                       = <key_with_valid_discount>-%tky ) TO failed-atras306.

      APPEND VALUE #( %tky                       = <key_with_valid_discount>-%tky
                      %msg                       = NEW /dmo/cm_flight_messages(
                                                        textid = /dmo/cm_flight_messages=>discount_invalid
                                                        severity = if_abap_behv_message=>severity-error )
                      %element-TotalPrice        = if_abap_behv=>mk-on
                      %op-%action-deductDiscount = if_abap_behv=>mk-on
                    ) TO reported-atras306.

      " 清空作为标识
      DELETE keys_with_valid_discount.
    ENDLOOP.

    " 如果为空标识折扣值有问题
    CHECK keys_with_valid_discount IS NOT INITIAL.

    " 读取相关的旅行实例数据（仅指预订费）
    READ ENTITIES OF zrap100_r_atras306 IN LOCAL MODE
        ENTITY atras306
        FIELDS ( BookingFee )
        WITH CORRESPONDING #( keys_with_valid_discount )
        RESULT DATA(travels).

    " 折扣 30%
    LOOP AT travels ASSIGNING FIELD-SYMBOL(<travel>).
      " DATA(reduced_fee) = <travel>-BookingFee * ( 1 - 3 / 10 ) .
      DATA percentage TYPE decfloat16.
      DATA(discount_percent) = keys_with_valid_discount[ KEY draft %tky = <travel>-%tky ]-%param-discount_percent.
      percentage =  discount_percent / 100 .
      DATA(reduced_fee) = <travel>-BookingFee * ( 1 - percentage ) .

      APPEND VALUE #( %tky       = <travel>-%tky
                    BookingFee = reduced_fee
                  ) TO travels_for_update.
    ENDLOOP.

    " 更新数据
    MODIFY ENTITIES OF zrap100_r_atras306 IN LOCAL MODE
        ENTITY atras306
        UPDATE FIELDS ( BookingFee )
        WITH travels_for_update.

    " 从结果中读取数据
    READ ENTITIES OF zrap100_r_atras306 IN LOCAL MODE
        ENTITY atras306
        ALL FIELDS WITH
        CORRESPONDING #( travels )
        RESULT DATA(travels_with_discount).

    " set action result
    result = VALUE #( FOR travel IN travels_with_discount ( %tky   = travel-%tky
                                                              %param = travel ) ).
  ENDMETHOD.

  METHOD copyTravel.
    " 新增操作：复制行

    DATA:
       travels       TYPE TABLE FOR CREATE zrap100_r_atras306\\atras306.

    " 删除带有初始%cid的旅行实例
    READ TABLE keys WITH KEY %cid = '' INTO DATA(key_with_inital_cid).
    ASSERT key_with_inital_cid IS INITIAL.

    " 从复制行中读取数据
    READ ENTITIES OF zrap100_r_atras306 IN LOCAL MODE
       ENTITY atras306
       ALL FIELDS WITH CORRESPONDING #( keys )
    RESULT DATA(travel_read_result)
    FAILED failed.

    LOOP AT travel_read_result ASSIGNING FIELD-SYMBOL(<travel>).
      " 填充数据
      APPEND VALUE #( %cid      = keys[ KEY entity %key = <travel>-%key ]-%cid
                     %is_draft = keys[ KEY entity %key = <travel>-%key ]-%param-%is_draft
                     %data     = CORRESPONDING #( <travel> EXCEPT TravelID )
                  )
      TO travels ASSIGNING FIELD-SYMBOL(<new_travel>).

      " 调整复制行的数据
      "" BeginDate 改为当前日期
      <new_travel>-BeginDate     = cl_abap_context_info=>get_system_date( ).
      "" EndDate 改为当前日期 + 30
      <new_travel>-EndDate       = cl_abap_context_info=>get_system_date( ) + 30.
      "" 状态改为 O
      <new_travel>-OverallStatus = 'O'."travel_status-open.
    ENDLOOP.

    " 创建新的BO实例
    MODIFY ENTITIES OF zrap100_r_atras306 IN LOCAL MODE
       ENTITY atras306
       CREATE FIELDS ( AgencyID CustomerID BeginDate EndDate BookingFee
                         TotalPrice CurrencyCode OverallStatus Description )
          WITH travels
       MAPPED DATA(mapped_create).

    " 更新
    mapped-atras306   =  mapped_create-atras306 .
  ENDMETHOD.

  METHOD acceptTravel.
    " 操作：接受旅行

    " 更改值
    MODIFY ENTITIES OF zrap100_r_atras306 IN LOCAL MODE
       ENTITY atras306
       UPDATE FIELDS ( OverallStatus )
       WITH VALUE #( FOR key IN keys ( %tky          = key-%tky
                                        OverallStatus = 'A' ) )  " 'A'
    FAILED failed
    REPORTED reported.

    " 读取操作
    READ ENTITIES OF zrap100_r_atras306 IN LOCAL MODE
       ENTITY atras306
       ALL FIELDS WITH
       CORRESPONDING #( keys )
       RESULT DATA(travels).

    " 更新字段
    result = VALUE #( FOR travel IN travels ( %tky   = travel-%tky
                                             %param = travel ) ).
  ENDMETHOD.

  METHOD rejectTravel.
    " 操作：拒绝旅行

    " 更改值
    MODIFY ENTITIES OF zrap100_r_atras306 IN LOCAL MODE
       ENTITY atras306
       UPDATE FIELDS ( OverallStatus )
       WITH VALUE #( FOR key IN keys ( %tky          = key-%tky
                                        OverallStatus = 'X' ) )  " 'X'
    FAILED failed
    REPORTED reported.

    " 读取操作
    READ ENTITIES OF zrap100_r_atras306 IN LOCAL MODE
       ENTITY atras306
       ALL FIELDS WITH
       CORRESPONDING #( keys )
       RESULT DATA(travels).

    " 更新字段
    result = VALUE #( FOR travel IN travels ( %tky   = travel-%tky
                                             %param = travel ) ).
  ENDMETHOD.

  METHOD get_instance_features.

    DATA: BEGIN OF travel_status,
            accepted TYPE char1 VALUE 'A',
            open     TYPE char1 VALUE 'O',
            rejected TYPE char1 VALUE 'X',
          END OF travel_status.

    " 读取特定数据（TravelID OverallStatus）
    READ ENTITIES OF zrap100_r_atras306 IN LOCAL MODE
      ENTITY atras306
        FIELDS ( TravelID OverallStatus )
        WITH CORRESPONDING #( keys )
      RESULT DATA(travels)
      FAILED failed.

    " 根据状态调整按钮
    result = VALUE #( FOR travel IN travels
                      ( %tky                   = travel-%tky

                        %features-%update      = COND #( WHEN travel-OverallStatus = travel_status-accepted
                                                         THEN if_abap_behv=>fc-o-disabled ELSE if_abap_behv=>fc-o-enabled   )
                        %features-%delete      = COND #( WHEN travel-OverallStatus = travel_status-open
                                                         THEN if_abap_behv=>fc-o-enabled ELSE if_abap_behv=>fc-o-disabled   )
                        %action-Edit           = COND #( WHEN travel-OverallStatus = travel_status-accepted
                                                         THEN if_abap_behv=>fc-o-disabled ELSE if_abap_behv=>fc-o-enabled   )
                        %action-acceptTravel   = COND #( WHEN travel-OverallStatus = travel_status-accepted
                                                          THEN if_abap_behv=>fc-o-disabled ELSE if_abap_behv=>fc-o-enabled   )
                        %action-rejectTravel   = COND #( WHEN travel-OverallStatus = travel_status-rejected
                                                          THEN if_abap_behv=>fc-o-disabled ELSE if_abap_behv=>fc-o-enabled   )
                        %action-deductDiscount = COND #( WHEN travel-OverallStatus = travel_status-open
                                                          THEN if_abap_behv=>fc-o-enabled ELSE if_abap_behv=>fc-o-disabled   )
                     ) ).

  ENDMETHOD.

ENDCLASS.
