CLASS zcl_rap100_service_atras306 DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC .

  PUBLIC SECTION.
    INTERFACES if_http_service_extension  .
  PROTECTED SECTION.
  PRIVATE SECTION.
ENDCLASS.



CLASS zcl_rap100_service_atras306 IMPLEMENTATION.
  METHOD if_http_service_extension~handle_request.

    CASE request->get_method(  ).

      WHEN CONV string( if_web_http_client=>get ).
        DATA(res) = `{`.

        res &&= `"NUM":12`.
        res &&= `}`.

        response->set_text( res ).
      WHEN CONV string( if_web_http_client=>post ).

    ENDCASE.
  ENDMETHOD.

ENDCLASS.
