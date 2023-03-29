CLASS zcl_rap100_gen_chinese_text DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC .

  PUBLIC SECTION.
    " 引入接口 adt 类运行
    INTERFACES if_oo_adt_classrun.
  PROTECTED SECTION.
  PRIVATE SECTION.
ENDCLASS.



CLASS zcl_rap100_gen_chinese_text IMPLEMENTATION.
  METHOD if_oo_adt_classrun~main.
    " 添加中文描述

    MODIFY /dmo/oall_stat_t FROM (
        SELECT
            FROM /dmo/oall_stat_t AS stat
            FIELDS overall_status AS overall_status,
                   '1' AS language,
                   text AS text
    ).
    COMMIT WORK.
    out->write( |/dmo/oall_stat_t update chinese. | ).

  ENDMETHOD.
ENDCLASS.
