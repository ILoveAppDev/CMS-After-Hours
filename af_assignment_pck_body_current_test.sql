--------------------------------------------------------
--  File created - Tuesday-December-29-2020   
--------------------------------------------------------
--------------------------------------------------------
--  DDL for Package Body AF_ASSIGNMENT_PCK
------------------------llllll--------------------------------

  CREATE OR REPLACE PACKAGE BODY "CMS"."AF_ASSIGNMENT_PCK" AS
    PROCEDURE oro(P_ADDBY varchar2, P_ADDDTTM date, P_MODBY varchar2, P_MODDTTM date, P_ORO_NAME varchar2, P_EFFECTIVE_DATE date) IS
        i NUMBER :=0;
        j NUMBER :=0;
        v_max_adddttm date;
        v_sysdate date;
        v_app_user varchar2(10) := v('APP_USER');
        v_pass_effective_time_old date;
        v_pass_effective_time_new date;
        v_cnt NUMBER;

                  
        CURSOR c_cur is 
            SELECT *
            FROM contract_IMSV7_ONCALL_LOCAL
            ORDER BY EFFECTIVE_DATE ASC
            FOR UPDATE;
            
        PROCEDURE update_duration(p_effective_date date) IS
            v_pass_effective_date_old date;
            v_effective_duration varchar2(20); 
            v_max_timestamp timestamp := null;
            v_adddttm date :=null;
        BEGIN
            --As the effective date precision is on Minute. There may have more than 1 record for the same effective date . Get the latest one according to the transaction timestamp. 
            select max(transaction_timestamp) into v_max_timestamp from AF_ONCALL_HIST where pass_effective_time_new=to_char(P_EFFECTIVE_DATE, 'DD-MON-YYYY HH24:MI');
            select to_date(pass_effective_time_old, 'DD-MON-YYYY HH24:MI'), to_char(round((p_effective_date-to_date(pass_effective_time_old, 'DD-MON-YYYY HH24:MI')),0))
            into v_pass_effective_date_old, v_effective_duration
            from AF_ONCALL_HIST 
            where on_call_id_new=9 and pass_effective_time_new=to_char(P_EFFECTIVE_DATE, 'DD-MON-YYYY HH24:MI') and transaction_timestamp=v_max_timestamp;
            update imsv7.oncall@contract set effective_duration=v_effective_duration, effective_end_date=p_effective_date where effective_date=v_pass_effective_date_old;
            select adddttm into v_adddttm from imsv7.oncall@contract where effective_date=v_pass_effective_date_old;
            --select to_date(pass_effective_time_new, 'DD-MON-YYYY HH24:MI') into v_pass_effective_date_new from AF_ONCALL_HIST where pass_effective_time_old=to_char(v_pass_effective_date_old, 'DD-MON-YYYY HH24:MI');
            if v_adddttm is null then  -- not IM
                update imsv7.oncall@contract set effective_duration=0, effective_end_date=p_effective_date where effective_date>v_pass_effective_date_old and effective_date<p_effective_date and effective_duration is null;
            else
                update imsv7.oncall@contract set effective_duration=to_char(round(v_pass_effective_date_old-effective_date,0)), effective_end_date=v_pass_effective_date_old where effective_date<v_pass_effective_date_old and adddttm>v_adddttm and effective_duration is null;
            end if;
            EXCEPTION
              WHEN OTHERS THEN
                NULL;
        END;
                  
    BEGIN
        --This block is to process the records in table contract_IMSV7_ONCALL_LOCAL
        BEGIN
            FOR c IN c_cur LOOP
                BEGIN
                    SAVEPOINT start_transaction; --1 by 1 to process the records
                    update_duration(c.effective_date);
                    insert into imsv7.oncall@contract(ADDBY,ADDDTTM,MODBY,MODDTTM,ORO_NAME,EFFECTIVE_DATE) values (c.ADDBY, c.ADDDTTM, c.MODBY, c.MODDTTM, c.ORO_NAME, c.EFFECTIVE_DATE);
                    --update_duration(c.effective_date);
                    delete from contract_IMSV7_ONCALL_LOCAL where current of c_cur;
                    EXCEPTION
                        WHEN DUP_VAL_ON_INDEX THEN  --
                            BEGIN
                                select adddttm into v_max_adddttm from imsv7.oncall@contract where effective_date=c.EFFECTIVE_DATE; 
                                IF v_max_adddttm<c.adddttm THEN
                                    UPDATE imsv7.oncall@contract SET MODBY=c.MODBY, MODDTTM=c.MODDTTM, ORO_NAME=c.ORO_NAME WHERE EFFECTIVE_DATE=c.EFFECTIVE_DATE;
                                    update_duration(c.effective_date);
                                END IF;                                
                                delete from contract_IMSV7_ONCALL_LOCAL where current of c_cur;
                                EXCEPTION
                                    WHEN others THEN
                                        ROLLBACK TO start_transaction;
                            END;
                        WHEN others THEN
                            ROLLBACK TO start_transaction;
                END;
            END LOOP; 
        END;

        --This block is to process the current assignment
        BEGIN
        
            update_duration(p_effective_date); 
            --This block is to see whether there is a hanging future assignment on the imsv7.oncall@contract
            select to_date(pass_effective_time_old, 'DD-MON-YYYY HH24:MI'), to_date(pass_effective_time_new, 'DD-MON-YYYY HH24:MI')
            into v_pass_effective_time_old, v_pass_effective_time_new
            from 
            ( select * 
              from AF_ONCALL_HIST 
              where on_call_id_new=9 and pass_effective_time_new=to_char(P_EFFECTIVE_DATE, 'DD-MON-YYYY HH24:MI')
              order by transaction_timestamp desc
            )
            where rownum=1;
            
            select count(1) into v_cnt from imsv7.oncall@contract where effective_date between v_pass_effective_time_old and v_pass_effective_time_new and effective_duration is null and effective_end_date is null;
            if v_cnt>0 then
                update imsv7.oncall@contract set modby=P_MODBY, moddttm=P_MODDTTM, oro_name=P_ORO_NAME, effective_date=P_EFFECTIVE_DATE where effective_date between v_pass_effective_time_old and v_pass_effective_time_new and effective_duration is null and effective_end_date is null;
            else
                insert into imsv7.oncall@contract(ADDBY,ADDDTTM,MODBY,MODDTTM,ORO_NAME,EFFECTIVE_DATE) values (P_ADDBY, P_ADDDTTM, P_MODBY, P_MODDTTM, P_ORO_NAME, P_EFFECTIVE_DATE);
            end if;
            --update_duration(p_effective_date);            
            EXCEPTION
                WHEN DUP_VAL_ON_INDEX THEN --The effective date precision is on Minute 
                    BEGIN
                        UPDATE imsv7.oncall@contract SET MODBY=P_MODBY, MODDTTM=P_MODDTTM, ORO_NAME=P_ORO_NAME WHERE EFFECTIVE_DATE=P_EFFECTIVE_DATE;
                        update_duration(p_effective_date);            
                        EXCEPTION
                            WHEN others THEN 
                                insert into contract_IMSV7_ONCALL_LOCAL(ADDBY,ADDDTTM,MODBY,MODDTTM,ORO_NAME,EFFECTIVE_DATE) values (P_ADDBY, P_ADDDTTM, P_MODBY, P_MODDTTM, P_ORO_NAME, P_EFFECTIVE_DATE);
                    END;    
                WHEN others THEN 
                    insert into contract_IMSV7_ONCALL_LOCAL(ADDBY,ADDDTTM,MODBY,MODDTTM,ORO_NAME,EFFECTIVE_DATE) values (P_ADDBY, P_ADDDTTM, P_MODBY, P_MODDTTM, P_ORO_NAME, P_EFFECTIVE_DATE);
        END;
        
        EXCEPTION
            WHEN others THEN
                raise_application_error(-20001,'DATA ERROR!!!');

    END ORO;

------------------------------------------------
-- update_assignment_tbl
------------------------------------------------
    procedure update_assignment_tbl (
        p_on_call_id          number,
        p_pass_onto           varchar2,
        p_pass_effective_time varchar2,
        p_specific_datetime   varchar2 default null
    )
    as
        v_passon_datetime           varchar2(40);
        v_pass_onto_to_be_replaced  varchar2(100);
        v_region_to_be_reassigned   varchar2(400);
        v_old_pass_onto_name        varchar2(100);

        v_old_pass_onto_email       varchar2(100);

        v_new_pass_onto_name        varchar2(100);
        v_new_pass_onto_email       varchar2(100);

        v_all_current_oncalls_found varchar2(1000);

        v_default_sender           varchar2(100);
        v_default_sender_name      varchar2(100);
        v_receivers                varchar2(400)  := null;
        v_emailsubject             varchar2(1000) := null;
        v_emailbody                varchar2(4000) := null;

        l_vc_arr1    APEX_APPLICATION_GLOBAL.VC_ARR2;

        v_job_num            int;
        v_diff               number;
        v_af_schjob_tctr_var varchar2(100) := null;

        v_tmp1               varchar2(100);
        v_tmp2               varchar2(100);
        v_tmp3               varchar2(100);
        v_tmp4               varchar2(100);

        v_new_hist_timestamp timestamp;


    begin

            if p_specific_datetime is not null 
               and
               TO_DATE( p_specific_datetime, 'dd-MON-yyyy HH24:MI' ) - sysdate < 0

            then
                raise_application_error( -20000, 'You cannot assign on-duty on any time earlier than now !');
            end if;


           -- because this is a new assignment, we need to 
           -- clean up all jobs for this unit, and then, if this is a future assignment, and scheduled job is 
           -- allowed by configuration table, will submit a new job

           for rec in (

                select job_num, transaction_timestamp
                from af_oncall_hist 
                where on_call_id_new = p_on_call_id and job_status = 'scheduled'   

            ) loop


                begin

                    dbms_job.remove(
                            job  => rec.job_num                   
                        ); 

                    update af_oncall_hist
                        set job_status = 'removed'
                    where on_call_id_new = p_on_call_id and transaction_timestamp = rec.transaction_timestamp;

                exception
                    when others then
                    null;

                end;

            end loop;

        -- Modified on Dec. 06, 2018
        /*
            Old code:
            select email into v_default_sender from users where upper(username) = upper( v('APP_USER') );
        */
        select email, first_name || ' ' || last_name into v_default_sender, v_default_sender_name from users where upper(username) = upper( v('APP_USER') );

        if p_specific_datetime is not null then

            v_passon_datetime := p_specific_datetime;

        elsif p_pass_effective_time = 'IM' then

            v_passon_datetime := sysdate;

        else

            select after_hour into v_passon_datetime from cms.af_oncall_info where on_call_id = p_on_call_id;

            if v_passon_datetime is not null then
                v_passon_datetime := TO_DATE(TO_CHAR(sysdate, 'MMDDYY') || ' ' || v_passon_datetime, 'MMDDYY HH24:MI:SS');
            else
                v_passon_datetime := TO_DATE(TO_CHAR(sysdate, 'MMDDYY') || ' ' || '17:00', 'MMDDYY HH24:MI:SS');
            end if;

        end if;


    --    raise_application_error( -20000, v_passon_datetime);

        select 
            pass_onto, 
            category_cd,
            upper( ret_oncall_pass_onto_info( p_on_call_id, 'fullname' ) ),
       --     a.first_name || ' ' || a.last_name,
            ret_oncall_pass_onto_info( p_on_call_id, 'email' )
          --  a.email
        into 
            v_pass_onto_to_be_replaced, 
            v_region_to_be_reassigned,
            v_old_pass_onto_name,
            v_old_pass_onto_email
        from af_oncall_info
        inner join users a
        on a.username = af_oncall_info.pass_onto
        where on_call_id = p_on_call_id;

  --      select a.first_name || ' ' || a.last_name into v_new_pass_onto_name from users a where username = p_pass_onto;
        select a.first_name || ' ' || a.last_name, email into v_new_pass_onto_name, v_new_pass_onto_email from users a where username = p_pass_onto;


        -- write to hist first, no trigger
   --     v_new_hist_timestamp := sysdate;
        v_new_hist_timestamp := systimestamp;


        INSERT INTO CMS.AF_ONCALL_HIST
        ( 
            ON_CALL_ID_OLD,
            ON_CALL_ID_NEW,
            USERNAME_OLD,
            USERNAME_NEW,
            CATEGORY_CD_OLD,
            CATEGORY_CD_NEW,
            PASS_ONTO_OLD,
            PASS_ONTO_NEW,
            PASS_EFFECTIVE_TIME_OLD,
            PASS_EFFECTIVE_TIME_NEW,
            TRANSACTION_TYPE, 
            TRANSACTION_BY,
            TRANSACTION_TIMESTAMP
        )
        VALUES
        (
            p_on_call_id,
            p_on_call_id,
            '',
            '',
            '',
            '',
            ret_oncall_pass_onto_info( p_on_call_id, 'pass_onto' ),
            p_pass_onto,
            ret_oncall_pass_onto_info( p_on_call_id, 'pass_effective_time' ),
            v_passon_datetime, 
            'UPDATE', 
            COALESCE(v('APP_USER'), user),
            v_new_hist_timestamp
        );


        -- After update, need to check if current saving value on af_oncall_info is 
        -- for future assignment, if it is, delete according hist record ( in current second location )from af_oncall_hist
        -- because it is not used any way and could disrupt the system

        select TO_DATE( pass_effective_time, 'dd-MON-yyyy HH24:MI' ) - sysdate
        into v_diff from af_oncall_info where on_call_id = p_on_call_id; 

        --if v_diff > 0 then 
        if v_diff > 0 and (p_pass_effective_time is null or p_pass_effective_time <> 'IM')  then --added by Lisa

            delete from af_oncall_hist WHERE TRANSACTION_TIMESTAMP
            = ( 
                select TRANSACTION_TIMESTAMP
                from
                ( 
                    select TRANSACTION_TIMESTAMP, ROW_NUMBER() OVER ( order by transaction_timestamp desc ) AS ROW_NUMBER 
                    from af_oncall_hist where on_call_id_old = p_on_call_id  
                    and  to_date( pass_effective_time_new , 'dd-MON-yyyy HH24:MI') > systimestamp --sysdate --added by Lisa
                )
                WHERE ROW_NUMBER = 2

            );

        end if;

        --Lisa added
        if v_diff>0 and p_pass_effective_time = 'IM' then
            update af_oncall_hist 
                set pass_onto_old = p_pass_onto ,                  
                    transaction_by      = v('APP_USER'),
                    transaction_timestamp  = systimestamp + 1/172800
            where on_call_id_old = p_on_call_id 
            and to_date(pass_effective_time_new,'dd-MON-yyyy HH24:MI') >= systimestamp ; -- sysdate ;
        end if;



        --
        -- If the info table store future assignment, 
        -- and the new assignment is immediate,
        -- it should not be overwritten
        if not ( v_diff > 0 and p_pass_effective_time is not null and p_pass_effective_time = 'IM' ) then

            update af_oncall_info 
                set pass_onto           = p_pass_onto, 
                    pass_effective_time = v_passon_datetime,
                    last_update_by      = v('APP_USER'),
                    last_update         = sysdate
            where on_call_id = p_on_call_id;

       end if;


        ------------------------------
        -- will only let current on-duty people receive email
        -- no future on-duty will get email
        -- Dec 07, 2018: but except current being assigned new on-duty 
        ------------------------------
      --  v_receivers := get_all_oncall_emails() || ',' || v_old_pass_onto_email;
        --v_receivers := GET_curr_ONCALL_EMAILS() || ',' || v_new_pass_onto_email;             
        --v_receivers := v_default_sender || ',' || v_old_pass_onto_email  || ',' || v_new_pass_onto_email;

        --Dec 7, 2018
        if p_specific_datetime is not null then
            v_receivers := v_default_sender || ',' || v_old_pass_onto_email  || ',' || v_new_pass_onto_email;
        else
            v_receivers := GET_curr_ONCALL_EMAILS() || ',' || v_new_pass_onto_email || ',' ||'TWCustomerCare@toronto.ca,TorontoWaterDispatch@toronto.ca';
        end if;
        v_emailsubject  := 'Do Not Reply - Next [ ' || v_region_to_be_reassigned || ' ] has been assigned';

        v_emailbody     := 'Hi All,' || CRLF || CRLF
                        || 'Please note next [ ' || v_region_to_be_reassigned || ' ] has been assigned by ' || v_default_sender_name || '. ' || CRLF || CRLF
                        || upper( v_new_pass_onto_name ) || ' will be replacing ' || v_old_pass_onto_name || ' as [ ' || v_region_to_be_reassigned || ' ], starting at: ' || v_passon_datetime
                        || '.' || CRLF || CRLF
                        || 'This is an automated email.  Please do not reply to this message. ' || CRLF || CRLF
                        || 'Thanks.' || CRLF || CRLF
                        || 'CMS Afterhours'
                        ;

        -- Modified on Dec. 06, 2018
        -- 
        v_default_sender  := 'cms@toronto.ca';

        send_useremail(
            p_sender       => v_default_sender,
            p_recipients   => v_receivers,
            p_replyto      => v_default_sender,
            p_subject      => v_emailsubject,
            p_message      => v_emailbody,
            P_is_body_html => false
        );


        if  p_on_call_id=9 and p_pass_effective_time='IM' then
            oro(v('APP_USER'), sysdate, v('APP_USER'), sysdate, P_PASS_ONTO,V_PASSON_DATETIME);
            --oro('wu sun', sysdate, 'wusun', sysdate,   'wusun test', sysdate);
        end if;

        -- Finally, schedule a job for next auto-notification
        -- usage of adding time interval: http://www.dba-oracle.com/t_date_math_manipulation.htm

        -- This is only for future on-duty assignment
        if to_date( v_passon_datetime, 'dd-MON-yyyy HH24:MI' ) > sysdate then

            -- get predefined variable from admin app
            v_af_schjob_tctr_var := trim( 
                                        DEF_SECURITY_ADMIN.get_app_param_value(
                                            p_param_name => 'af_schedulejob_timecontrol_var'
                                        ) 
                                    );

            /*
            -- stupid oracle does not know how to convert '2/24/60' to number !!!

            if instr( v_af_schjob_tctr_var, '/' ) <> 0 then

                if regexp_count( v_af_schjob_tctr_var, '/' ) = 1 then 

                    v_tmp1 := substr( v_af_schjob_tctr_var, 1, instr( v_af_schjob_tctr_var, '/' ) - 1 );
                    v_tmp2 := substr( v_af_schjob_tctr_var, instr( v_af_schjob_tctr_var, '/' ) + 1, length( v_af_schjob_tctr_var ) - instr( v_af_schjob_tctr_var, '/' ) );

                    v_af_schjob_tctr_var := v_tmp1 / v_tmp2;

                elsif regexp_count( v_af_schjob_tctr_var, '/' ) = 2 then 

                    -- take '10/24/60' as example
                    -- this will return '10'
                    v_tmp1 := substr( v_af_schjob_tctr_var, 1, instr( v_af_schjob_tctr_var, '/' ) - 1 );

                    -- this will return '24/60'                 
                    v_tmp2 := substr( v_af_schjob_tctr_var, instr( v_af_schjob_tctr_var, '/' ) + 1, length( v_af_schjob_tctr_var ) - instr( v_af_schjob_tctr_var, '/' ) );

                    -- this will return '24'
               --     v_tmp3 := substr( v_tmp2, instr( v_tmp2, '/' ) + 1, length( v_tmp2 ) - instr( v_tmp2, '/' ) );
                    v_tmp3 := substr( v_tmp2, 1, instr( v_tmp2, '/' ) - 1 );

                    -- this will return '60'
                    v_tmp4 := substr( v_tmp2, instr( v_tmp2, '/' ) + 1, length( v_tmp2 ) - instr( v_tmp2, '/' ) );

                    v_af_schjob_tctr_var := v_tmp1 / v_tmp3 / v_tmp4;

                end if;

            end if;
            */

            -- if the variable is defined as "prohibit", then stop doing the whole email thing and schedule job
            if v_af_schjob_tctr_var is not null and upper( v_af_schjob_tctr_var ) <> upper( 'prohibit' ) then 

                v_af_schjob_tctr_var := v_af_schjob_tctr_var / 24 / 60;

                if to_date( to_date( v_passon_datetime, 'dd-MON-yyyy HH24:MI' ) - to_number( v_af_schjob_tctr_var ) ) - sysdate < 0.0 then

                    EMAIL_FOR_NEXT_AVAI_ASSIGNMENT( p_on_call_id, COALESCE(v('APP_USER'), user) );

                else

                    dbms_job.submit(
                            job         => v_job_num,
                            --what        => 'begin CMS.AF_ASSIGNMENT_PCK.EMAIL_FOR_NEXT_AVAI_ASSIGNMENT(' || p_on_call_id || ', COALESCE(v(''APP_USER''), user) ); end;', 
                            what        => 'begin CMS.AF_ASSIGNMENT_PCK.EMAIL_FOR_NEXT_AVAI_ASSIGNMENT(' || p_on_call_id || ',''' || COALESCE(v('APP_USER'), user) || '''); end;', 

                            next_date   => to_date( v_passon_datetime, 'dd-MON-yyyy HH24:MI' ) - to_number( v_af_schjob_tctr_var ), 
                         --   next_date   => sysdate+2/24/60, 
                            interval    => 'null'
                       --     no_parse    => false,
                       --     instance    => ANY_INSTANCE,
                       --     force       => true
                        );  


                    -- Need to save the job number into history table for future reference
                    update CMS.AF_ONCALL_HIST
                        set job_num = v_job_num,
                            job_status = 'scheduled'
                    where TRANSACTION_TIMESTAMP = v_new_hist_timestamp and ON_CALL_ID_NEW = p_on_call_id;


                end if;



            end if;

        end if;

    end update_assignment_tbl;


------------------------------------------------
-- bulk_update_assignment_tbl
------------------------------------------------
    procedure bulk_update_assignment_tbl (
        p_bulk_on_call_id          varchar2,
        p_bulk_pass_onto           varchar2,
        p_bulk_pass_effective_time varchar2
    ) 
    as

        l_vc_arr1    APEX_APPLICATION_GLOBAL.VC_ARR2;
        l_vc_arr2    APEX_APPLICATION_GLOBAL.VC_ARR2;
        l_vc_arr3    APEX_APPLICATION_GLOBAL.VC_ARR2;

    begin

        l_vc_arr1 := APEX_UTIL.STRING_TO_TABLE( p_bulk_on_call_id );
        l_vc_arr2 := APEX_UTIL.STRING_TO_TABLE( p_bulk_pass_onto );
        l_vc_arr3 := APEX_UTIL.STRING_TO_TABLE( p_bulk_pass_effective_time );

        FOR z IN 1..l_vc_arr2.count LOOP

                update_assignment_tbl (
                    p_on_call_id          => l_vc_arr1(z),
                    p_pass_onto           => l_vc_arr2(z),
                    p_pass_effective_time => l_vc_arr3(z)
                  );

        END LOOP;

    end bulk_update_assignment_tbl;

------------------------------------------------
-- is_appuser_among_oncalls
------------------------------------------------  
    function is_appuser_among_oncalls
    return boolean
    as
        v_cnt         int     := 0;
        v_ret_boolean boolean := false;
    begin

        select count(*) into v_cnt from cms.af_oncall_info where upper(pass_onto) = upper( v('APP_USER') ) ;

        if v_cnt > 0 then
            v_ret_boolean := true;
        end if;

        return v_ret_boolean;

    end is_appuser_among_oncalls;

------------------------------------------------
-- is_appuser_has_access
------------------------------------------------
    function is_appuser_has_access(
        p_app_id    varchar2,
        p_priv_name varchar2
    )
    return boolean
    as     
    begin
        if p_app_id = '2' then
        return DEF_SECURITY_ADMIN.is_appuser_has_access(
            p_app_code  => 'CMS_AF',
            p_priv_name => p_priv_name,
            p_username  => v('APP_USER')
        );
        else
        return DEF_SECURITY_ADMIN.is_appuser_has_access(
            p_app_code  => p_app_id,
            p_priv_name => p_priv_name,
            p_username  => v('APP_USER')
        );
        end if;
    end is_appuser_has_access;

------------------------------------------------
-- has_app_access
------------------------------------------------ 
    function has_app_access(
        p_app_id    varchar2
    )
    return boolean
    as
    begin


        return DEF_SECURITY_ADMIN.has_app_access(
            p_app_code  => p_app_id,
            p_username  => v('APP_USER')
        );


    end has_app_access;


------------------------------------------------
-- get_all_oncall_candidates
------------------------------------------------    
    procedure get_all_oncall_candidates
    is
        v_output varchar2(1000);
    begin

        get_pair_values_output (
            p_output_format => 'json',
            p_qry_str       => QRYSTR_GET_ALL_QUALIFY_ONCALLS,
            p_output_allstr => v_output
        );

    end get_all_oncall_candidates;

------------------------------------------------
-- get_all_oncall_cadidates_table
------------------------------------------------    
    function get_all_oncall_cadidates_table
    return list_obj_table PIPELINED
    is
        row_rec list_obj;

        v_option_val   varchar2(2000);
        v_option_dis   varchar2(2000);

        TYPE cur_type IS REF CURSOR;
        c              cur_type;
        cnt            int;
    begin

        OPEN c FOR QRYSTR_GET_ALL_QUALIFY_ONCALLS;
        loop

            cnt := cnt + 1;

            FETCH c INTO v_option_dis, v_option_val;
            EXIT WHEN c%NOTFOUND;

            v_option_dis := REPLACE(REPLACE(REGEXP_REPLACE(v_option_dis, '([/\|"])', '\\\1', 1, 0), chr(9), '\t'), chr(10), '\n') ;
            v_option_val := REPLACE(REPLACE(REGEXP_REPLACE(v_option_val, '([/\|"])', '\\\1', 1, 0), chr(9), '\t'), chr(10), '\n') ;

            SELECT v_option_dis, v_option_val
            INTO row_rec.label, row_rec.target FROM DUAL;

            PIPE ROW (row_rec);

        end loop;
        close c;

        return;

    end get_all_oncall_cadidates_table;

------------------------------------------------
-- get_all_unit_users_table
------------------------------------------------    
    function get_all_unit_users_table
    return list_obj_table PIPELINED
    is
        row_rec list_obj;

        v_option_val   varchar2(2000);
        v_option_dis   varchar2(2000);

        TYPE cur_type IS REF CURSOR;
        c              cur_type;
        cnt            int;
    begin

        OPEN c FOR QRYSTR_GET_ALL_ACTIVE_USERS;
        loop

            cnt := cnt + 1;

            FETCH c INTO v_option_dis, v_option_val;
            EXIT WHEN c%NOTFOUND;

            v_option_dis := REPLACE(REPLACE(REGEXP_REPLACE(v_option_dis, '([/\|"])', '\\\1', 1, 0), chr(9), '\t'), chr(10), '\n') ;
            v_option_val := REPLACE(REPLACE(REGEXP_REPLACE(v_option_val, '([/\|"])', '\\\1', 1, 0), chr(9), '\t'), chr(10), '\n') ;

            SELECT v_option_dis, v_option_val
            INTO row_rec.label, row_rec.target FROM DUAL;

            PIPE ROW (row_rec);

        end loop;
        close c;

        return;

    end get_all_unit_users_table;

------------------------------------------------
-- get_all_current_oncalls
------------------------------------------------   
    procedure get_all_current_oncalls (
        p_output_format     varchar2 default 'json',
        p_all_found   out   varchar2 
    )
    is    
    begin

        get_pair_values_output (
            p_output_format => p_output_format,
            p_qry_str        => QRYSTR_GET_ALL_CURRENT_ONCALLS,
            p_output_allstr  => p_all_found
        );

    end get_all_current_oncalls;

------------------------------------------------
-- get_all_oncall_emails
------------------------------------------------   
    function get_all_oncall_emails 
    return varchar2
    is
        ret_val      varchar2(2000);

    begin

        get_pair_values_output (
            p_output_format => 'email',
            p_qry_str        => QRYSTR_GET_ALL_CURRENT_ONCALLS,
            p_output_allstr  => ret_val
        );

        return ret_val;

    end get_all_oncall_emails;

------------------------------------------------
-- get_curr_oncall_emails
-- This is called by following two procedures to get Cc for emails.
--  (1) procedure email_for_next_avai_assignment()
--  (2) procedure update_assignment_tbl()
------------------------------------------------   
    function get_curr_oncall_emails(
        p_specific_oncall_id number default null,
        p_specific_delimiter varchar2 default null
    )
    return varchar2
    is
        ret_val      varchar2(2000) := null;
        v_email      varchar2(100);
        
        TYPE cur_type IS REF CURSOR;
        c              cur_type;
        
        CURSOR c_oncall_emails IS 
         select a.email 
            from USERS a 
            inner join table( AF_ASSIGNMENT_PCK.get_all_curr_only_oncall_table( p_specific_oncall_id ) ) b 
            on a.username = b.pass_onto 
            order by 1;
   
    begin
    
        OPEN c_oncall_emails;
        loop
              
            FETCH c_oncall_emails INTO v_email;
            EXIT WHEN c_oncall_emails%NOTFOUND;
            
            -- added on Dec 20, 2018   
            if p_specific_delimiter is null then
                ret_val := ret_val || ',' || v_email;
            else
                ret_val := ret_val || p_specific_delimiter || v_email;
            end if;
            
        end loop;
        close c_oncall_emails;
        
        -- added on Dec 20, 2018
        if p_specific_delimiter is null then
            
            ret_val := remove_duplic_in_delimited_str(
                    p_in_str         => ret_val,
                    p_delimited_char => ','
                );
                
        else
        
            ret_val := remove_duplic_in_delimited_str(
                    p_in_str         => ret_val,
                    p_delimited_char => p_specific_delimiter
                );
                
        end if;
            
        
                
        return ret_val;
        
    end get_curr_oncall_emails;

------------------------------------------------
-- get_pair_values_output_as_json
------------------------------------------------       
    procedure get_pair_values_output (
        p_output_format      varchar2 default 'json',
        p_qry_str            varchar2,
        p_output_allstr out  varchar2  
    )
    is

        v_retval       clob;
        json_all       clob;

        TYPE cur_type IS REF CURSOR;
        c              cur_type;

        v_option_val   varchar2(2000);
        v_option_dis   varchar2(2000);
        v_email        varchar2(2000);

        v_temp_val     varchar2(2000) := null;

        json_comp      varchar2(4000);

        cnt            int := 0;
        is_found       boolean;
        l_vc_arr1      APEX_APPLICATION_GLOBAL.VC_ARR2;

    begin

        json_all := '';

        json_comp := 
                    '{'
                  || '"option_dis":"' || 'None' || '",'
                  || '"option_val":"' || 'None' || '"'
                  || '}';

        OPEN c FOR p_qry_str;
        loop

            cnt := cnt + 1;

            FETCH c INTO v_option_dis, v_option_val, v_email;
            EXIT WHEN c%NOTFOUND;

            v_option_dis := REPLACE(REPLACE(REGEXP_REPLACE(v_option_dis, '([/\|"])', '\\\1', 1, 0), chr(9), '\t'), chr(10), '\n') ;
           v_option_val := REPLACE(REPLACE(REGEXP_REPLACE(v_option_val, '([/\|"])', '\\\1', 1, 0), chr(9), '\t'), chr(10), '\n') ;


            if p_output_format = 'email' then

                is_found := false;

                l_vc_arr1  := APEX_UTIL.STRING_TO_TABLE( v_temp_val );

                FOR z IN 1..l_vc_arr1.count LOOP

                    if l_vc_arr1(z) is not null and trim( l_vc_arr1(z) ) = trim( v_option_val ) then
                        is_found := true;

                    end if;            

                END LOOP;

                if is_found = false then

                    if cnt = 1 then

                        v_temp_val := v_option_val;
                        p_output_allstr := v_email;

                    else

                        v_temp_val := v_temp_val || ':' || v_option_val;
                        p_output_allstr := p_output_allstr || ',' || v_email;


                    end if;


                end if;

            else /* id_only */
                p_output_allstr := p_output_allstr || ':' || v_option_val;
            end if;


            if p_output_format = 'json' then

                json_comp := 
                        '{'
                      || '"option_dis":"' || v_option_dis || '",'
                      || '"option_val":"' || v_option_val || '"'
                      || '}';

                if  cnt = 1 then

                    json_all := json_comp;

                else

                    json_all := json_all || ',' || json_comp;

                end if;


            end if;

        end loop;
        close c;

        if p_output_format = 'json' then

           v_retval := '[' || json_all || ']';

            ----------------------------------------
            -- This is for test when debugging
            ----------------------------------------
       --     v_retval := '[{"option_dis":"value1","option_val":"value2"},{"option_dis":"value3","option_val":"value4"}]';

            htp.p(v_retval);


        end if;

        return;

    end get_pair_values_output;


------------------------------------------------
-- send_useremail
------------------------------------------------ 
    procedure send_useremail(
        p_sender      varchar2,
        p_recipients  varchar2,
        p_cc          varchar2 DEFAULT null,
        p_bcc         varchar2 DEFAULT 'cms@toronto.ca',
        p_replyto     varchar2,
        p_subject     varchar2,
        p_message     varchar2,
        P_is_body_html boolean DEFAULT false
      )
      as
        real_sender  varchar2(1000);
        real_to      varchar2(2000);
        real_subject varchar2(2000);
        real_message varchar2(10000);
        real_cc      varchar2(1000);
        real_bcc     varchar2(1000);
        real_replyto varchar2(1000);

        v_test_mode          varchar2(100);
        v_test_user_email    varchar2(100);
        v_test_user_email_1  varchar2(100);
        v_email_func_disable varchar2(100);

      begin


        real_sender  := p_sender;        
        real_to      := p_recipients;
        real_subject := p_subject;
        real_message := p_message;
        real_cc      := p_cc;
        real_bcc     := p_bcc;
        real_replyto := p_replyto;

        real_to := remove_duplic_in_delimited_str(
                    p_in_str         => real_to,
                    p_delimited_char => ','
                );

        real_cc := remove_duplic_in_delimited_str(
                    p_in_str         => real_cc,
                    p_delimited_char => ','
                );
        real_bcc := remove_duplic_in_delimited_str(
                    p_in_str         => real_bcc,
                    p_delimited_char => ','
                );

        real_replyto := remove_duplic_in_delimited_str(
                    p_in_str         => real_replyto,
                    p_delimited_char => ','
                );

        begin

            v_test_mode           := DEF_SECURITY_ADMIN.get_app_param_value(
                                            p_param_name => 'af_test_mode'
                                        );

            v_test_user_email     := DEF_SECURITY_ADMIN.get_app_param_value(
                                            p_param_name => 'af_test_user_email'
                                        );

            v_email_func_disable := DEF_SECURITY_ADMIN.get_app_param_value(
                                            p_param_name => 'af_email_func_disable'
                                        );

        exception
            when others then
                v_test_mode          := PCK_TEST_MODE;
                v_test_user_email    := PCK_TEST_USER_EMAIL;
                v_email_func_disable := PCK_EMAIL_FUNC_DISABLE;

        end;

        if upper( v_test_mode ) = 'Y' then

            v_test_user_email_1 := v_test_user_email;

            if instr( v_test_user_email, ',' ) > 0 then
                v_test_user_email_1:= substr( v_test_user_email, 1, instr( v_test_user_email, ',' ) - 1 );
            end if;

            real_sender  := upper( v_test_user_email_1 );
            real_to      := upper( v_test_user_email );
            real_subject := 'CMF AF is now configured as Test Mode in CMS Admin app ! - ' || p_subject;
            real_message := 'CMF AF is now configured as Test Mode in CMS Admin app ! - ' || CRLF || CRLF 
                            || 'Original p_recipients [ ' || p_recipients || ' ]' || CRLF || CRLF 
                            || 'Original p_cc [ ' || p_cc || ' ]' || CRLF || CRLF 
                            || 'Original p_bcc [ ' || p_bcc || ' ]' || CRLF || CRLF 
                            || 'Original p_replyto [ ' || p_replyto || ' ]' || CRLF || CRLF 
                            || 'Original p_sender [ ' || p_sender || ' ]' || CRLF || CRLF
                            || 'original message: ' || CRLF || CRLF
                            || p_message;

            real_cc      := null;
            real_bcc     := null;
            real_replyto := v_test_user_email;

        end if;

        if upper( v_email_func_disable ) = 'N' then

            if P_is_body_html = true then

                APEX_MAIL.SEND(

                    p_to                        => real_to,
                    p_from                      => real_sender,
                    p_body                      => null,
                    p_body_html                 => real_message,
                    p_subj                      => real_subject,
                    p_cc                        => real_cc,
                    p_bcc                       => real_bcc,
                    p_replyto                   => real_replyto

                    );
                APEX_MAIL.PUSH_QUEUE;
            else

                APEX_MAIL.SEND(

                    p_to                        => real_to,
                    p_from                      => real_sender,
                    p_body                      => real_message,
                    p_body_html                 => null,
                    p_subj                      => real_subject,
                    p_cc                        => real_cc,
                    p_bcc                       => real_bcc,
                    p_replyto                   => real_replyto

                    );

            APEX_MAIL.PUSH_QUEUE;
            end if;

        end if;

      end send_useremail;


------------------------------------------------
-- get_email_menu_table
------------------------------------------------      
    function get_email_menu_table (
        p_oncall_id number
    )
    return list_obj_table PIPELINED
    is

        row_rec list_obj;

    begin

        for rec in (

            select 1, 
                   'Email '||users.first_name || ' ' || users.last_name label, 
                   --'mailto:'||users.email target
                   'javascript:var mailTab=window.open(''mailto:'||users.email||''',''_blank''); mailTab.focus();  
                   setTimeout(function(){if(!mailTab.document.hasFocus()) { mailTab.close();}}, 300);' target


            from users
            inner join af_oncall_info
       --     on users.username = af_oncall_info.pass_onto
            on users.username = AF_ASSIGNMENT_PCK.ret_oncall_pass_onto_info( p_oncall_id, 'pass_onto' )
            where on_call_id = p_oncall_id

            union

            select 1, 
                   'Email all afterhours' label, 
                   --'mailto:' || AF_ASSIGNMENT_PCK.get_all_oncall_emails  target
                   'javascript:var mailTab=window.open(''mailto:'||replace(AF_ASSIGNMENT_PCK.get_curr_oncall_emails,',',';')||''',''_blank''); mailTab.focus();  
                   setTimeout(function(){if(!mailTab.document.hasFocus()) { mailTab.close();}}, 300);' target

            from dual


        ) loop

                    SELECT rec.label, rec.target
                        INTO row_rec.label, row_rec.target FROM DUAL;

                    PIPE ROW (row_rec);

        end loop;

        return;

    end get_email_menu_table;


------------------------------------------------
-- get_call_menu_table
------------------------------------------------      
    function get_call_menu_table (
        p_oncall_id number
    )
    return list_obj_table PIPELINED
    is

        row_rec list_obj;

    begin

        for rec in (

            select 1, 
                   case 
                      when business_cell is not null then 'Mobile'
                      else null --'No Mobile Number'
                   end label, 
                   case 
                      when business_cell is not null then 'Tel:1' || business_cell
                      else null              
                   end target
            from users
            inner join af_oncall_info           
        --    on users.username = af_oncall_info.pass_onto
            on users.username = AF_ASSIGNMENT_PCK.ret_oncall_pass_onto_info( p_oncall_id, 'pass_onto' )
            where on_call_id = p_oncall_id

            union

            select 2, 
                   case 
                      when telephone is not null then 'Desk'
                      else null --'No Desk Number'
                   end label, 
                   case 
                      when telephone is not null then 'Tel:1' || telephone

                      else null            
                   end target
            from users
            inner join af_oncall_info
        --    on users.username = af_oncall_info.pass_onto
            on users.username = AF_ASSIGNMENT_PCK.ret_oncall_pass_onto_info( p_oncall_id, 'pass_onto' )
            where on_call_id = p_oncall_id

        ) loop

                IF rec.target is not null THEN
                    SELECT rec.label, rec.target
                        INTO row_rec.label, row_rec.target FROM DUAL;

                    PIPE ROW (row_rec);
                END IF;
        end loop;

        return;

    end get_call_menu_table;


------------------------------------------------
-- ret_oncall_pass_onto_info
--
-- Right now there are following types can be returned
-- 'fullname'
-- 'pass_onto'
-- 'title'
-- 'business_cell'
-- 'email'
-- 'pass_effective_time'

------------------------------------------------        
    function ret_oncall_pass_onto_info(
        p_oncall_id    number,
        p_ret_type     varchar2,
        p_get_future   boolean default false
    )
    return varchar2
    as
    
        v_fullname              varchar2(200);
        v_pass_onto             varchar2(200);
        v_title                 varchar2(200);
        v_business_cell         varchar2(200);
        v_email                 varchar2(200);
        v_effective_timestamp   varchar2(200);
    --    v_effective_timestamp   timestamp;
        v_trans_timestamp       timestamp;
        
        v_ret           varchar2(200) := 'unknown type';
        
        v_diff          number;
        
    begin
    
  --  raise_application_error( -20000, p_oncall_id);
    
        select TO_DATE( pass_effective_time, 'dd-MON-yyyy HH24:MI' ) - sysdate
        into v_diff
        from af_oncall_info where on_call_id = p_oncall_id;
        
        if 
            v_diff < 0.0 and p_get_future = false 
            or
            v_diff > 0.0 and p_get_future = true 
        then 
        
            select 
                b.first_name || ' ' || b.last_name,
                a.pass_onto,
                b.title,
                b.business_cell,
                b.email,
                a.pass_effective_time,
                a.last_update
            into
                v_fullname,
                v_pass_onto,
                v_title,
                v_business_cell,
                v_email,
                v_effective_timestamp,
                v_trans_timestamp
                
            from af_oncall_info a, users b 
            where a.pass_onto = b.username
            and on_call_id = p_oncall_id;
        
        else
        
            select 
                b.first_name || ' ' || b.last_name,
                a.pass_onto,
                b.title,
                b.business_cell,
                b.email,
                a.pass_effective_time,
                a.transaction_timestamp
            into
                v_fullname,
                v_pass_onto,
                v_title,
                v_business_cell,
                v_email,
                v_effective_timestamp,
                v_trans_timestamp
                
            from 
            (
                select 
                
                    a.pass_onto_old pass_onto,
                    a.pass_effective_time_old pass_effective_time,
                    
                    a.on_call_id_old on_call_id,
                    a.transaction_timestamp
                /*
                    a.pass_onto_new pass_onto,
                    a.pass_effective_time_new pass_effective_time,
                    a.on_call_id_new on_call_id
                   */
                from af_oncall_hist a
                inner join
                (
                /*  
                    select 
                        on_call_id_old,
                        max( transaction_timestamp ) transaction_timestamp
                    from af_oncall_hist
                    group by on_call_id_old
                  */
                    
                    select *
                    from
                    (
                     
                        select *              
                        from af_oncall_hist            
                        where on_call_id_old = p_oncall_id
                        and TO_DATE( pass_effective_time_old, 'dd-MON-yyyy HH24:MI' ) - sysdate < 0
                   --     and TO_DATE( pass_effective_time_new, 'dd-MON-yyyy HH24:MI' ) - CURRENT_DATE < 0
                   --     order by pass_effective_time_old desc
                        order by transaction_timestamp desc                      

                   
                   
                   /*
                        select *              
                        from af_oncall_hist            
                        where on_call_id_old = p_oncall_id
                        and TO_DATE( pass_effective_time_new, 'dd-MON-yyyy HH24:MI' ) - sysdate < 0
                    --    and TO_DATE( pass_effective_time_new, 'dd-MON-yyyy HH24:MI' ) - CURRENT_DATE < 0
                        order by transaction_timestamp desc
                     */
                    ) where rownum < 2
                   
                ) b
           --     on a.on_call_id_old = b.on_call_id_old
           --     and a.transaction_timestamp = b.transaction_timestamp
                
                on a.on_call_id_new = b.on_call_id_new
                and a.pass_effective_time_new = b.pass_effective_time_new
                and a.pass_onto_new = b.pass_onto_new
                --and a.pass_onto_old = b.pass_onto_old commented out by lisa
                and nvl(a.pass_onto_old,0) = nvl(b.pass_onto_old,0) --added by lisa
                
            ) a, users b 
            where a.pass_onto = b.username
            and on_call_id = p_oncall_id;
            
        end if;
        
        if lower(p_ret_type) = 'fullname' then
            v_ret := v_fullname;
        elsif lower(p_ret_type) = 'pass_onto' then
            v_ret := v_pass_onto; 
        elsif lower(p_ret_type) = 'title' then
            v_ret := v_title; 
        elsif lower(p_ret_type) = 'business_cell' then
            v_ret := v_business_cell; 
        elsif lower(p_ret_type) = 'email' then
            v_ret := v_email;
        elsif lower(p_ret_type) = 'pass_effective_time' then
        --    v_ret := TO_CHAR( v_effective_timestamp, 'dd-MON-yyyy HH24:MI' ); 
            v_ret := v_effective_timestamp; 
        elsif lower(p_ret_type) = 'trans_timestamp' then
            v_ret := TO_CHAR( v_trans_timestamp, 'dd-MON-yyyy HH24:MI:SS' ) ; 
        end if;
        
        return v_ret;
    
    exception
        when no_data_found then
            return null;
            
    end ret_oncall_pass_onto_info;


------------------------------------------------
-- ret_future_oncall_info
------------------------------------------------        
    function ret_future_oncall_info(
        p_oncall_id    number
    )
    return varchar2
    as
        v_ret                 varchar2(200) := NO_NEXT_SCHEDULE_TEXT;
        v_diff                number;
        v_pass_effective_time varchar2(200);

        c                     utl_smtp.connection;

    begin

        -- This is for debugging current_date and sysdate
        /*
        c := utl_smtp.open_connection('mail.toronto.ca', 25); -- SMTP on port 25 
        utl_smtp.helo(c, 'mail.toronto.ca');
        utl_smtp.mail(c, 'cms@toronto.ca');
        utl_smtp.rcpt(c, 'xli5@toronto.ca');

        utl_smtp.data(c,'From: cms@toronto.ca' || utl_tcp.crlf ||
        'To: xli5@toronto.ca' || utl_tcp.crlf ||
        'Subject: debug info from scheduled job' || utl_tcp.crlf ||
        'calling ret_future_oncall_info() ,  CURRENT_DATE -> ' || CURRENT_DATE || utl_tcp.crlf || 
        'calling ret_future_oncall_info() ,  sysdate -> ' || sysdate 
        );
        utl_smtp.quit(c);
        */

    --    select pass_effective_time, TO_DATE( pass_effective_time, 'dd-MON-yyyy HH24:MI' ) - CURRENT_DATE
        select pass_effective_time, TO_DATE( pass_effective_time, 'dd-MON-yyyy HH24:MI' ) - sysdate
        into v_pass_effective_time, v_diff
        from af_oncall_info where on_call_id = p_oncall_id;

        -- This is for debugging
        /*
        c := utl_smtp.open_connection('mail.toronto.ca', 25); -- SMTP on port 25 
        utl_smtp.helo(c, 'mail.toronto.ca');
        utl_smtp.mail(c, 'cms@toronto.ca');
        utl_smtp.rcpt(c, 'xli5@toronto.ca');

        utl_smtp.data(c,'From: cms@toronto.ca' || utl_tcp.crlf ||
        'To: xli5@toronto.ca' || utl_tcp.crlf ||
        'Subject: debug info from scheduled job' || utl_tcp.crlf ||
        'calling ret_future_oncall_info() ,  v_pass_effective_time -> ' || v_pass_effective_time || utl_tcp.crlf || 
        'calling ret_future_oncall_info() ,  v_diff -> ' || v_diff || utl_tcp.crlf ||
        'calling ret_future_oncall_info() ,  p_oncall_id -> ' || p_oncall_id 
        );
        utl_smtp.quit(c);
        */

        if v_diff > 0.0 then

            -- format: [ Next on-call: Maurice Balaski - MON, 10-SEP-2018 14:00 ]
            v_ret := '[ Next: '
                    || ret_oncall_pass_onto_info( p_oncall_id, 'fullname', true )
                    || ' - '
                    || TO_CHAR ( TO_DATE( v_pass_effective_time, 'dd-MON-yyyy HH24:MI' ), 'Dy' )                    
                    || ', ' 
                    || TO_CHAR ( TO_DATE( ret_oncall_pass_onto_info( p_oncall_id, 'pass_effective_time', true ), 'dd-MON-yyyy HH24:MI'), 'dd-Mon-yyyy HH24:MI' )                     
                    || ' ]';

        end if;

        return v_ret;

    exception
        when others then
            -- This is for in case, we cannot get any error log, at least we get email
            c := utl_smtp.open_connection('mail.toronto.ca', 25); -- SMTP on port 25 
            utl_smtp.helo(c, 'mail.toronto.ca');
            utl_smtp.mail(c, 'cms@toronto.ca');
            utl_smtp.rcpt(c, 'xli5@toronto.ca');

            utl_smtp.data(c,'From: cms@toronto.ca' || utl_tcp.crlf ||
            'To: xli5@toronto.ca' || utl_tcp.crlf ||
           'Subject: error from scheduled job' || utl_tcp.crlf ||
            'ret_future_oncall_info() Error -> ' || SQLCODE || ' - ' || SQLERRM );
            utl_smtp.quit(c);

    end ret_future_oncall_info;


------------------------------------------------
-- get_all_curr_fu_oncall_table
------------------------------------------------      
    function get_all_curr_fu_oncall_table
        return oncall_obj_table PIPELINED
    as
        row_rec                   oncall_obj;
        v_new_pass_effective_time varchar2(200);
        v_new_pass_onto           varchar2(200);
        v_diff                    number;
    begin

        for rec in (

            select on_call_id, 
                   pass_onto, 
                   pass_effective_time
            from af_oncall_info          
            where active = 'A'
        ) loop

            select TO_DATE( pass_effective_time, 'dd-MON-yyyy HH24:MI' ) - sysdate
            into v_diff
            from af_oncall_info where on_call_id = rec.on_call_id;

            if ( v_diff > 0.0 ) then

                v_new_pass_effective_time := AF_ASSIGNMENT_PCK.ret_oncall_pass_onto_info(
                                                p_oncall_id    => rec.on_call_id,
                                                p_ret_type     => 'pass_effective_time'
                                                /*,
                                                p_get_current  => false,
                                                p_get_future   => true
                                                */
                                            );        


                v_new_pass_onto := AF_ASSIGNMENT_PCK.ret_oncall_pass_onto_info(
                                            p_oncall_id    => rec.on_call_id,
                                            p_ret_type     => 'pass_onto',                               
                                            p_get_future   => true
                                        );

               SELECT rec.on_call_id, v_new_pass_onto, v_new_pass_effective_time
                INTO row_rec.on_call_id, row_rec.pass_onto, row_rec.pass_effective_time FROM DUAL;

                PIPE ROW (row_rec);

            end if;

            SELECT rec.on_call_id, rec.pass_onto, rec.pass_effective_time
                INTO row_rec.on_call_id, row_rec.pass_onto, row_rec.pass_effective_time FROM DUAL;

            PIPE ROW (row_rec);

        end loop;

    end get_all_curr_fu_oncall_table;


------------------------------------------------
-- get_all_curr_only_oncall_table
-- This is to make sure email list triggered
-- by email button on page 11 only for current on-calls
------------------------------------------------      
------------------------------------------------
-- get_all_curr_only_oncall_table
-- This is to make sure email list triggered
-- by email button on page 11 only for current on-calls
------------------------------------------------      
    function get_all_curr_only_oncall_table (
        p_specific_oncall_id number default null
    )
    return oncall_obj_table PIPELINED
    as
        row_rec                   oncall_obj;
        v_new_pass_effective_time varchar2(200);
        v_new_pass_onto           varchar2(200);
        v_diff                    number;
    begin
    
        for rec in (

            select on_call_id, 
                   pass_onto, 
                   pass_effective_time
            from af_oncall_info  
            where active = 'A'
            and unit_group in 
            (
               select unit_group from af_oncall_info 
               where ( 
                       p_specific_oncall_id is null
                       or
                       p_specific_oncall_id is not null and p_specific_oncall_id = on_call_id
                )
            )

        ) loop

            select TO_DATE( pass_effective_time, 'dd-MON-yyyy HH24:MI' ) - sysdate
            into v_diff
            from af_oncall_info where on_call_id = rec.on_call_id;
        
            -- If current info table stores future assgnment, we need to find
            -- current from hist table
            if ( v_diff > 0.0 ) then
            
                v_new_pass_effective_time := AF_ASSIGNMENT_PCK.ret_oncall_pass_onto_info(
                                                p_oncall_id    => rec.on_call_id,
                                                p_ret_type     => 'pass_effective_time',
                                          --      p_get_future   => true
                                                p_get_future   => false
                                            );        
          
            
                v_new_pass_onto := AF_ASSIGNMENT_PCK.ret_oncall_pass_onto_info(
                                            p_oncall_id    => rec.on_call_id,
                                            p_ret_type     => 'pass_onto',
                                       --     p_get_future   => true
                                            p_get_future   => false
                                        );
            
                SELECT rec.on_call_id, v_new_pass_onto, v_new_pass_effective_time
                INTO row_rec.on_call_id, row_rec.pass_onto, row_rec.pass_effective_time FROM DUAL;
                
                PIPE ROW (row_rec);
                
            else
            
                SELECT rec.on_call_id, rec.pass_onto, rec.pass_effective_time
                    INTO row_rec.on_call_id, row_rec.pass_onto, row_rec.pass_effective_time FROM DUAL;
    
                PIPE ROW (row_rec);
            
            end if;

        end loop;
        
    end get_all_curr_only_oncall_table;
    

------------------------------------------------
-- email_for_next_avai_assignment
-- This is the scheduled job
------------------------------------------------      
    procedure email_for_next_avai_assignment(
        p_specific_oncall_id       number default null,
        p_specific_trans_username  varchar2 default null
    )
    is
        v_return               VARCHAR2(200);
        v_next_assignee        VARCHAR2(200);
        v_next_assignee_email  VARCHAR2(200);
        v_next_schedule        VARCHAR2(200);
        v_next_transaction_by  VARCHAR2(200);
        
        v_next_oncall_id       number;
        
        v_next_assignee_prev        VARCHAR2(200) := null;
        v_next_schedule_prev        VARCHAR2(200) := null;      
        v_next_oncall_id_prev       number        := 0;
        v_next_transaction_by_prev  VARCHAR2(200) := null;
        v_trans_timestamp VARCHAR2(50);
        loc_1 int;
        loc_2 int;
        loc_3 int;
        loc_4 int;
        
        v_default_sender           varchar2(100);
        v_receivers                varchar2(1000)  := null;
        v_cc                       varchar2(1000) := null;
        v_emailsubject             varchar2(1000) := null;
        v_emailbody                varchar2(4000) := null;
        
        v_pass_onto_to_be_replaced  varchar2(100);
        v_region_to_be_reassigned   varchar2(400);
        v_old_pass_onto_name        varchar2(100);
        
        v_old_pass_onto_email       varchar2(100);
        
        c                           utl_smtp.connection;
        
   --     v_temp_oncall_id            NUMBER;
    begin
    
         -- This is for debugging
         /*
        c := utl_smtp.open_connection('mail.toronto.ca', 25); -- SMTP on port 25 
        utl_smtp.helo(c, 'mail.toronto.ca');
        utl_smtp.mail(c, 'cms@toronto.ca');
        utl_smtp.rcpt(c, 'xli5@toronto.ca');
    
        utl_smtp.data(c,'From: cms@toronto.ca' || utl_tcp.crlf ||
        'To: xli5@toronto.ca' || utl_tcp.crlf ||
        'Subject: debug info from scheduled job' || utl_tcp.crlf ||
        'p_specific_oncall_id -> ' || p_specific_oncall_id || utl_tcp.crlf ||
        'p_specific_trans_username -> ' || p_specific_trans_username || utl_tcp.crlf 
        
        );
        utl_smtp.quit(c);
        */
        
        
        
        for rec in (

            select on_call_id
            from af_oncall_info          
            where on_call_id = nvl(p_specific_oncall_id, on_call_id)
            
        ) loop
            
            -- Set a temp var
         --   v_temp_oncall_id := rec.on_call_id;
              
        --    if p_specific_oncall_id is not null then
        --        v_temp_oncall_id := p_specific_oncall_id;               
        --    end if;
            
            v_return := AF_ASSIGNMENT_PCK.RET_FUTURE_ONCALL_INFO(
                                P_ONCALL_ID =>  rec.on_call_id
                              );

            -- This is for debugging
            /*
            c := utl_smtp.open_connection('mail.toronto.ca', 25); -- SMTP on port 25 
            utl_smtp.helo(c, 'mail.toronto.ca');
            utl_smtp.mail(c, 'cms@toronto.ca');
            utl_smtp.rcpt(c, 'xli5@toronto.ca');
        
            utl_smtp.data(c,'From: cms@toronto.ca' || utl_tcp.crlf ||
            'To: xli5@toronto.ca' || utl_tcp.crlf ||
            'Subject: debug info from scheduled job' || utl_tcp.crlf ||
            'v_return -> ' || v_return || utl_tcp.crlf ||
            'on_call_id -> ' || rec.on_call_id || utl_tcp.crlf 
            
            );
            utl_smtp.quit(c);
        */
        
            if v_return <> NO_NEXT_SCHEDULE_TEXT then

                -- This is for debugging
                /*
                c := utl_smtp.open_connection('mail.toronto.ca', 25); -- SMTP on port 25 
                utl_smtp.helo(c, 'mail.toronto.ca');
                utl_smtp.mail(c, 'cms@toronto.ca');
                utl_smtp.rcpt(c, 'xli5@toronto.ca');
            
                utl_smtp.data(c,'From: cms@toronto.ca' || utl_tcp.crlf ||
                'To: xli5@toronto.ca' || utl_tcp.crlf ||
                'Subject: debug info from scheduled job' || utl_tcp.crlf ||
                'future on-duty assignment is found, continue ! ' 
                
                );
                utl_smtp.quit(c);
                */
                
                -- example: [ Next on-call: David Cox - Monday   , 13-AUG-2018 09:15 ]
                loc_1 := instr( v_return, ':', 1 );
                loc_2 := instr( v_return, '-', loc_1 );
                loc_3 := instr( v_return, ',', loc_2 );
                
                v_next_oncall_id := rec.on_call_id;
                
                -- Should read: David Cox
                v_next_assignee := trim( substr( v_return, loc_1 + 1, loc_2 - loc_1 - 1 ) );
                
                -- Should read: 13-AUG-2018 09:15
                v_next_schedule := trim( substr( v_return, loc_3 + 1, length( v_return ) - loc_3 - 1 ) );
                
                 DBMS_OUTPUT.PUT_LINE('v_next_assignee = ' || v_next_assignee);
                 DBMS_OUTPUT.PUT_LINE('v_next_schedule = ' || v_next_schedule);
            
                -- find out the person who actually saved the assignment and use
                -- his/her email as email 's send_from
                
                if p_specific_oncall_id is not null then
                
                    if p_specific_trans_username is not null then
                        v_next_transaction_by := p_specific_trans_username;
                    else
                    
                        begin
                    
                            select transaction_by into v_next_transaction_by
                            from af_oncall_hist 
                            where on_call_id_new = rec.on_call_id
                            and to_date( pass_effective_time_new, 'dd-MON-yyyy HH24:MI' ) > sysdate
                            and rownum < 2
                            order by transaction_timestamp desc;
                        
                            -- This is the final step, send email directly to : cms@toronto.ca
                        exception
                            when others then
                                v_next_transaction_by := 'cms';
                        end;
                
                    end if;
                    
                else
                
                    begin
                    
                        select transaction_by into v_next_transaction_by
                        from af_oncall_hist 
                        where on_call_id_new = rec.on_call_id
                        and to_date( pass_effective_time_new, 'dd-MON-yyyy HH24:MI' ) > sysdate
                        and rownum < 2
                        order by transaction_timestamp desc;
                    
                    exception
                        when others then
                        
                            -- This is for in case, we cannot get any error log, at least we get email
                            c := utl_smtp.open_connection('mail.toronto.ca', 25); -- SMTP on port 25 
                            utl_smtp.helo(c, 'mail.toronto.ca');
                            utl_smtp.mail(c, 'cms@toronto.ca');
                            utl_smtp.rcpt(c, 'xli5@toronto.ca');
                        
                            utl_smtp.data(c,'From: cms@toronto.ca' || utl_tcp.crlf ||
                            'To: xli5@toronto.ca' || utl_tcp.crlf ||
                            'Subject: error from scheduled job' || utl_tcp.crlf ||
                            'Error -> ' || SQLCODE || ' - ' || SQLERRM );
                            utl_smtp.quit(c);

                            goto to_loopend;
                    end;
                
                end if;
               
                -- This is for debugging
                /*
                c := utl_smtp.open_connection('mail.toronto.ca', 25); -- SMTP on port 25 
                utl_smtp.helo(c, 'mail.toronto.ca');
                utl_smtp.mail(c, 'cms@toronto.ca');
                utl_smtp.rcpt(c, 'xli5@toronto.ca');
            
                utl_smtp.data(c,'From: cms@toronto.ca' || utl_tcp.crlf ||
                'To: xli5@toronto.ca' || utl_tcp.crlf ||
                'Subject: debug info from scheduled job' || utl_tcp.crlf ||
                'v_next_assignee_prev -> ' || v_next_assignee_prev || utl_tcp.crlf ||
                'v_next_assignee -> ' || v_next_assignee || utl_tcp.crlf ||
                'v_next_schedule -> ' || v_next_schedule || utl_tcp.crlf ||
                'v_next_transaction_by -> ' || v_next_transaction_by || utl_tcp.crlf ||
                'v_next_schedule_prev -> ' || v_next_schedule_prev || utl_tcp.crlf 
                
                );
                utl_smtp.quit(c);
                */
                
                if v_next_assignee_prev is null then
                         
                    v_next_assignee_prev  := v_next_assignee;
                    v_next_schedule_prev  := v_next_schedule;
                    v_next_oncall_id_prev := v_next_oncall_id;
                    
                    v_next_transaction_by_prev := v_next_transaction_by;
                    
               
                else
                
                    if to_date( v_next_schedule, 'dd-MON-yyyy HH24:MI' ) < to_date( v_next_schedule_prev, 'dd-MON-yyyy HH24:MI' ) then
                    
                        v_next_assignee_prev  := v_next_assignee;
                        v_next_schedule_prev  := v_next_schedule;
                        v_next_oncall_id_prev := v_next_oncall_id;
                        v_next_transaction_by_prev := v_next_transaction_by;
                    
                    
                    end if;
                    
                end if;
                
                
            end if;

<<to_loopend>>   
            null;
      --      if p_specific_oncall_id is not null then
      --          exit;
      --      end if;
                      
        end loop;
        
      --  v_next_assignee_prev :='Wu Sun';
      
       -- This is for debugging
       /*
        c := utl_smtp.open_connection('mail.toronto.ca', 25); -- SMTP on port 25 
        utl_smtp.helo(c, 'mail.toronto.ca');
        utl_smtp.mail(c, 'cms@toronto.ca');
        utl_smtp.rcpt(c, 'xli5@toronto.ca');
    
        utl_smtp.data(c,'From: cms@toronto.ca' || utl_tcp.crlf ||
        'To: xli5@toronto.ca' || utl_tcp.crlf ||
        'Subject: debug info from scheduled job' || utl_tcp.crlf ||
        'v_next_assignee_prev -> ' || v_next_assignee_prev );
        utl_smtp.quit(c);
        */
        
        if v_next_assignee_prev is not null then

            select 
                pass_onto, 
                category_cd
          --      a.first_name || ' ' || a.last_name,
          --      a.email
            into 
                v_pass_onto_to_be_replaced, 
                v_region_to_be_reassigned
       --         v_old_pass_onto_name,
           --     v_old_pass_onto_email
            from af_oncall_info
        --    inner join users a
        --    on a.username = af_oncall_info.pass_onto
            where on_call_id = v_next_oncall_id_prev;

            v_next_assignee_email := ret_oncall_pass_onto_info( v_next_oncall_id_prev, 'email', true );
            v_pass_onto_to_be_replaced := ret_oncall_pass_onto_info( v_next_oncall_id_prev, 'fullname', false );
            
         --   v_default_sender := 'xli5@toronto.ca';
            DBMS_OUTPUT.PUT_LINE('v_next_transaction_by_prev = ' || v_next_transaction_by_prev);
            
            begin
                select email into v_default_sender from users where upper( username ) = upper( v_next_transaction_by_prev );
            exception
                when others then
                  v_default_sender := v_next_transaction_by_prev || '@toronto.ca';
            end;
            
            ----------------------
            -- Added by Shawn On Nov. 13, 2018
            -- start to use this system email
            ----------------------
            v_default_sender := 'cms@toronto.ca';
            
            v_receivers     := v_next_assignee_email;
             
            ----------------------------
            -- Only current on-duty people will get email
            -- no future on-duty will get email
            ----------------------------
        --    v_cc            := get_all_oncall_emails() || ',' || v_old_pass_onto_email;
            v_cc            := GET_curr_ONCALL_EMAILS( p_specific_oncall_id ) || ',' || v_old_pass_onto_email;
            
            v_emailsubject  := 'Do Not Reply - ' || v_next_assignee_prev || ' on-call duty as [ ' || v_region_to_be_reassigned || ' ] starting at [ ' || v_next_schedule_prev || ' ]';
            
            v_emailbody     := 'Hi ' || v_next_assignee_prev || ', ' || CRLF || CRLF
                            || 'This is a friendly reminder that your on-call duty as [ ' || v_region_to_be_reassigned || ' ] will start at  ' || v_next_schedule_prev || '.   ' || CRLF || CRLF
                            || 'You will be replacing current on-call [ ' || v_pass_onto_to_be_replaced || ' ]' || CRLF || CRLF
                            || 'This is an automated email.  Please do not reply to this message.' || CRLF || CRLF
                            || 'Thank you.' || CRLF || CRLF
                         --   || 'CMS Afterhours' || CRLF || CRLF
                            || 'CMS Afterhours' || getDBServerName() || CRLF || CRLF
                            -- Can comment this out if necessary
                            || output_all_assgn_in_text_tbl
                            ;
                            
             DBMS_OUTPUT.PUT_LINE('v_receivers = ' || v_receivers);
             DBMS_OUTPUT.PUT_LINE('v_emailsubject = ' || v_emailsubject);
             DBMS_OUTPUT.PUT_LINE('v_emailbody = ' || v_emailbody);
              
            -- This check added on Jan 11, 2019 by Shawn
            -- Previously, if new future assignment is created, adn there is no enough time
            -- to submit job, this function will be called directly from APEX session
            -- and then APEX app will get JSON.PArser error !!!!
            if v('APP_USER') is null then
            
                tmp_create_apex_session(
                    p_app_id      => 150,
                    p_app_user    => 'cms',
              --      p_app_user    => 'xli5',
                    p_app_page_id => 1
                );
                        
            end if;
           
           
    --     raise_application_error( -20000, v_receivers);
    --   dbms_output.put_line('sending email to:  ' || v_default_sender); 

              
            
            
            if trim(v_next_oncall_id_prev)='9' then
                --v_trans_timestamp := ret_oncall_pass_onto_info(v_next_oncall_id_prev, 'trans_timestamp', true);
              --  oro(p_specific_trans_username, to_date(p_change_timestamp, 'dd-MON-yyyy HH24:MI:SS'), null,null, substr(v_next_assignee_prev, 1, 10), to_date(v_next_schedule_prev,'DD-MON-YYYY HH24:MI'));
                --oro(p_specific_trans_username, to_date(p_change_timestamp, 'dd-MON-yyyy HH24:MI:SS'), null,null, ret_oncall_pass_onto_info( v_next_oncall_id_prev, 'pass_onto', true ), to_date(TO_CHAR(ret_oncall_pass_onto_info( v_next_oncall_id_prev, 'trans_timestamp', true ),'MM/DD/YYYY HH24:MI:SS'), 'MM/DD/YYYY HH24:MI:SS'));
                
                oro(
                        p_specific_trans_username, 
               --         to_date(p_change_timestamp, 'dd-MON-yyyy HH24:MI:SS'), 
                        to_date( ret_oncall_pass_onto_info( v_next_oncall_id_prev, 'trans_timestamp', true ), 'dd-MON-yyyy HH24:MI:SS'), 
                        p_specific_trans_username,
                        to_date( ret_oncall_pass_onto_info( v_next_oncall_id_prev, 'trans_timestamp', true ), 'dd-MON-yyyy HH24:MI:SS'), 
                        ret_oncall_pass_onto_info( v_next_oncall_id_prev, 'pass_onto', true ), 
                        to_date(v_next_schedule_prev,'DD-MON-YYYY HH24:MI')
                    );
                    
                --oro(v_next_transaction_by, sysdate, v_next_transaction_by, sysdate, substr(v_next_assignee_prev, 1, 10), to_date(substr(v_trans_timestamp, 1,17),'DD-MM-YY HH24:MI:SS'));
            end if;

            
            /*BEGIN
                v_trans_timestamp := ret_oncall_pass_onto_info(v_next_oncall_id_prev, 'trans_timestamp', true);
                --oro(v_next_transaction_by, sysdate, v_next_transaction_by, sysdate,  substr(v_trans_timestamp,1,5), v_next_schedule_prev);
                oro(v_next_transaction_by, sysdate, v_next_transaction_by, sysdate, 'WU', v_next_schedule_prev);
                exception
                    when others then
                    --oro(v_next_transaction_by, sysdate, v_next_transaction_by, sysdate,  v_trans_timestamp, v_next_schedule_prev);
                    oro(v_next_transaction_by, sysdate, v_next_transaction_by, sysdate,  v_next_assignee_prev, v_next_schedule_prev);
            END;*/
            
            send_useremail(
                p_sender       => v_default_sender,
                p_recipients   => v_receivers,
                p_cc           => v_cc|| ',' ||'cms@toronto.ca,lsitu@toronto.ca',
                p_replyto      => v_default_sender,
                p_subject      => v_emailsubject,
                p_message      => v_emailbody,
                P_is_body_html => false
            );
   
           

        end if;
        
        -- This is for in case, we cannot get any error log, at least we get email
        /*
        c := utl_smtp.open_connection('mail.toronto.ca', 25); -- SMTP on port 25 
        utl_smtp.helo(c, 'mail.toronto.ca');
        utl_smtp.mail(c, 'cms@toronto.ca');
        utl_smtp.rcpt(c, 'xli5@toronto.ca');
    
        utl_smtp.data(c,'From: cms@toronto.ca' || utl_tcp.crlf ||
        'To: xli5@toronto.ca' || utl_tcp.crlf ||
        'Subject: message from scheduled job' || utl_tcp.crlf ||
        'Job Completes -> ' || SQLCODE || ' - ' || SQLERRM );
        utl_smtp.quit(c);
        */
    
    end email_for_next_avai_assignment;

------------------------------------------------
-- tmp_create_apex_session
-- This is for oracle scheduled job outside the APEX
------------------------------------------------     
    PROCEDURE tmp_create_apex_session(
          p_app_id IN apex_applications.application_id%TYPE,
          p_app_user IN apex_workspace_activity_log.apex_user%TYPE,
          p_app_page_id IN apex_application_pages.page_id%TYPE DEFAULT 1
    ) 
    AS
      l_workspace_id apex_applications.workspace_id%TYPE;
      l_cgivar_name  owa.vc_arr;
      l_cgivar_val   owa.vc_arr;
    BEGIN

      htp.init; 

      l_cgivar_name(1) := 'REQUEST_PROTOCOL';
      l_cgivar_val(1) := 'HTTP';

      owa.init_cgi_env( 
        num_params => 1, 
        param_name => l_cgivar_name, 
        param_val => l_cgivar_val ); 

      SELECT workspace_id
      INTO l_workspace_id
      FROM apex_applications
      WHERE application_id = p_app_id;

      wwv_flow_api.set_security_group_id(l_workspace_id); 

      apex_application.g_instance := 1; 
      apex_application.g_flow_id := p_app_id; 
      apex_application.g_flow_step_id := p_app_page_id; 

      apex_custom_auth.post_login( 
        p_uname => p_app_user, 
     --   p_session_id => null, -- could use APEX_CUSTOM_AUTH.GET_NEXT_SESSION_ID
        p_session_id => APEX_CUSTOM_AUTH.GET_NEXT_SESSION_ID,
    --    p_session_id => V('APP_SESSION'),
        p_app_page => apex_application.g_flow_id||':'||p_app_page_id); 

    END tmp_create_apex_session;

    function remove_duplic_in_delimited_str(
        p_in_str            varchar2,
        p_delimited_char    varchar2 DEFAULT ':'
    ) return varchar2
    as
        v_ret varchar2(2000) := null;

        is_found       boolean;
        l_vc_arr1      APEX_APPLICATION_GLOBAL.VC_ARR2;
        l_vc_arr2      APEX_APPLICATION_GLOBAL.VC_ARR2;

        v_cnt          int := 0;

    begin

        if trim( p_in_str ) is null then        
            return null;       
        end if;

        l_vc_arr1  := APEX_UTIL.STRING_TO_TABLE( 
                        p_string    => p_in_str,
                        p_separator => p_delimited_char
                    );

        FOR z IN 1..l_vc_arr1.count LOOP

            is_found := false;

            if v_cnt > 0 then

                if trim( l_vc_arr1(z) ) is not null then

                    FOR z1 IN 1..l_vc_arr2.count LOOP

                        if trim( l_vc_arr1(z) ) = l_vc_arr2(z1) then
                            is_found := true;               
                        end if;            

                    END LOOP;

                end if;

            end if;

            if is_found = false then

                v_cnt := v_cnt + 1;
                l_vc_arr2(v_cnt) := trim( l_vc_arr1(z) );                

            end if;

        END LOOP;


        v_ret := APEX_UTIL.TABLE_TO_STRING (
                    p_table     => l_vc_arr2,
                    p_string    => p_delimited_char
                    ); 


        return v_ret;

    END remove_duplic_in_delimited_str;

    function is_card_active(
        p_oncall_id number
    ) return varchar2
    as
        v_ret varchar2(10);
    begin

        select active into v_ret from af_oncall_info where on_call_id = p_oncall_id;
        return v_ret;

    end is_card_active;
    
------------------------------------------------
-- output_all_assgn_in_text_tbl
------------------------------------------------        
    function output_all_assgn_in_text_tbl 
    return clob
    is
        v_ret clob := null;
        
        v_pad_num_1 int := 10;
        v_pad_num_2 int := 110;
        v_pad_num_3 int := 50;
        v_pad_num_4 int := 300;
        v_pad_num_5 int := 50;
        
        v_col_title_1 varchar2(200) := 'ID';
        v_col_title_2 varchar2(200) := 'Unit';
        v_col_title_3 varchar2(200) := 'Current on-duty';
        v_col_title_4 varchar2(200) := 'Future on-duty';
        v_col_title_5 varchar2(200) := 'Effective Time';
        
        v_tmp_str     varchar2(300);
        v_tmp_str_1   varchar2(300);
        v_tmp_str_2   varchar2(300);
        
    begin
    
    
        v_ret := '***********************************************' || CRLF 
                || 'This table shows all current / future on-duty assignments for all units'
                || CRLF || CRLF
              --  || rpad( v_col_title_1, v_pad_num_1 - length(v_col_title_1), ' ' )
             --   || rpad( v_col_title_2, v_pad_num_2 - length(v_col_title_2), ' ' )
             --   || rpad( v_col_title_3, v_pad_num_3 - length(v_col_title_3), ' ' )
             --   || rpad( v_col_title_4, v_pad_num_4 - length(v_col_title_4), ' ' )
                
            --    || rpad( v_col_title_5, v_pad_num_5 - length(v_col_title_5) )
             --   || CRLF
                ;
        
        for rec in (

            select 
            
                on_call_id,
                trim( category_cd ) category_cd
                
            from af_oncall_info          
            where active = 'A'
            order by to_number( on_call_id )
            
        ) loop
          
            v_tmp_str := trim( 
                            ret_oncall_pass_onto_info (
                                P_ONCALL_ID   =>  rec.on_call_id,
                                p_ret_type    => 'fullname'
                            ) 
                        );
           /*  
            v_tmp_str_1 := trim( 
                            ret_oncall_pass_onto_info (
                                P_ONCALL_ID   =>  rec.on_call_id,
                                p_ret_type    => 'fullname',
                                p_get_current => false,
                                p_get_future  => true
                            ) 
                        );
            
            v_tmp_str_2 := trim( 
                            ret_oncall_pass_onto_info (
                                P_ONCALL_ID   =>  rec.on_call_id,
                                p_ret_type    => 'pass_effective_time',
                                p_get_current => false,
                                p_get_future  => true
                            ) 
                        );
             */       
            v_tmp_str_1 := trim( 
                              RET_FUTURE_ONCALL_INFO(
                                P_ONCALL_ID =>  rec.on_call_id
                              )
                            );
            if  v_tmp_str_1 = NO_NEXT_SCHEDULE_TEXT then
                v_tmp_str_1 := null;
            end if;
            
            v_ret :=  v_ret || CRLF 
                 --     || rpad( rec.on_call_id,    v_pad_num_1 - length(rec.on_call_id),         ' ' )
                --      || rpad( rec.category_cd,   v_pad_num_2 - length(rec.category_cd),        ' ' )
                --      || rpad( v_tmp_str_1,         v_pad_num_3 - length(v_tmp_str_1), ' ' ) 
                --      || rpad( v_tmp_str_1,       v_pad_num_4 - length(v_tmp_str_1), ' ' ) 
                      || rpad( rec.on_call_id, v_pad_num_1 - length(rec.on_call_id), ' ' )
                      || rec.category_cd || CRLF
                      || chr(09) || v_tmp_str || ' '
                      || v_tmp_str_1 || CRLF
                    --   || rpad( v_tmp_str_2,       v_pad_num_5 - length(v_tmp_str_2) ) 
                      ;
                              
        end loop;
        
       
        return v_ret;
        
    end output_all_assgn_in_text_tbl;


------------------------------------------------
-- getDBServerName
------------------------------------------------     
    function getDBServerName return varchar2
    is
        v_nm varchar2(100) := null;
        
    begin
    
        v_nm := sys_context('USERENV','SERVER_HOST');
        
        if v_nm = 'ytfvdor01' then
            return '@dev';
        elsif v_nm = 'wtor11hovm' then
            return '@test';
        -- return null if it is production
        elsif instr( v_nm, 'wpor13' ) > 0 then
            return null;
        else
            return v_nm;
        end if;
        
    end getDBServerName;
    
    END AF_ASSIGNMENT_PCK;

/
