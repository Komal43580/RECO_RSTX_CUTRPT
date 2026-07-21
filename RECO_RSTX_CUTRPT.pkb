create or replace PACKAGE BODY      "RECO_RSTX_CUTRPT"
AS
  -- CONTINUE HERE BUGS FOUND
  -- 1) MPTX - The "uncuttable parts" exceptions does not work off the
  --    requirement date (what if a shipment from yesterday is APPROVED ??)
  --    (Fix this in the MPTX schedule)
  -- 2) MPTX - Does not support BACKORDER
  --    (Fix this in the MPTX schedule and MPTX Daily Act Rpt)
  -- 3) Does MPTX handle Double/Single/NONE punched (D504, S504, and N504) ??
  --    Does this handle it ?? The Steel Daily Activity report does not support NP
  -- 4) MPTX - ARE EXCEPTIONS HANDLED WELL ??
-- 
-- CONTINUE HERE -- CONTINUE HERE
-- Implement reco_rstx_calday.pocket_max_length.
-- Everything works fine right now.
-- But this pocket_max_length would allow us to handle times
-- when a specific pocket-bin is disabled or something
-- 
-- CONTINUE HERE -- CONTINUE HERE
-- Raw-Stl handling is not used anymore (but it is still tracked).
-- You can all parts that were taken out by searching for this comment:
-- : -- CONTINUE HERE RAWSTL REMOVED
-- If you uncomment every spot with that comment, then rawsteel handling
-- will be used again
-- 
-- CONTINUE HERE -- CONTINUE HERE
-- The overage/inventory factor
-- What kind of overage?
-- How much in inventory?
-- Change it to read inventory quantity MIN/MAX
-- 
-- CONTINUE HERE -- CONTINUE HERE 
-- For 505 and 506 part, you need a "perfect recursive optimize" option,
-- to reduce the waste for meeting the requirement
-- Also, for 505 and 506, when a 28 footer is needed, you will prefer
-- the 28-20 cut over the 28-12-8 because 506 likes "larger" overage bars
-- 
-- CONTINUE HERE -- CONTINUE HERE
-- If a day needs 70 BLACK and 70 GALV then the requirements will satisfy
-- the BLACK first, then the galv may have to wait a few days.
-- Really, it should satisfy the GALV first, and bring the black handling
-- closer to the actual due-date of the job
-- 
-- CONTINUE HERE -- CONTINUE HERE
-- Change 49' bars / 48' bars from "either-or" to set-per-day
-- 
-- CONTINUE HERE -- CONTINUE HERE
-- Rare Length -> Apply to satisfy rare length is not optimal,
-- it could possibly combine rare-lengths into the same cut/mtx/bar
-- Also, when cutting 32' bar,
-- It always gives 32-8-8, which is a lot of overage for the 8' bar
-- Perhaps maybe it should only use 32-16
-- 
-- CONTINUE HERE -- CONTINUE HERE
-- When cutting 18-12-10-8 then let's say program picks 400 RUNS
-- Well this generates 150 overage for the 8' bar.
-- Perhaps it should have been dialed down to 300 maybe, only in future?
-- 
-- CONTINUE HERE -- CONTINUE HERE
-- The Previous Days / Late days are hardcoded.
-- This has caused problems where everything that is "late" is lumped together
-- This should realistically be changed so that it goes day-by-day for every
-- late requirement, and it should not lump them all together if they're
-- over 3 days late
  
  vc_DebugString varchar2(4000);
  
  vn_BizDaysAhead_ToDoBlk number := 6; -- CONTINUE HERE convert to user parameter
  
  vn_RoundingForPunch number := 25; -- CONTINUE HERE convert to user parameter
  
  vn_MaxQtyPerDayPunch number := 2500; -- CONTINUE HERE convert to user parameter
  
  vn_PunchReportRounding number := 100;
  
  vn_MaxQtyPerDayGalv number := 8000; -- CONTINUE HERE convert to user parameter
  
  -- Roughly 3 weeks of days to log PER EACH CutSch-refresh
  vn_MaxDaysToLogPerSch number := 21;
  
  -- Category Set IDs that are important
  nCSetR number;
  nCSetB number;
  nCSetG number;
  nCSetN number;
  
  bSummaryReport BOOLEAN:= FALSE;



--------------------------------------------------------------------------------
PROCEDURE add_pockets_for_day (given_calday_id IN number,
  given_p1_type IN varchar2,given_p2_type IN varchar2,
  given_p3_type IN varchar2,given_p4_type IN varchar2,
  given_p5_type IN varchar2,given_p6_type IN varchar2,
  given_p7_type IN varchar2,given_p8_type IN varchar2)
IS
BEGIN -- add_pockets_for_day
  
  INSERT INTO reco_rstx_day_pocket
    ( day_pocket_id,calday_id,storage_capacity,pocket_number,
      parttype,max_length,last_update_date,last_updated_by,
      creation_date,created_by,last_update_login )
  SELECT  reco_rstx_day_pocket_seq.nextval,
          given_calday_id,
          storage_capacity,
          pocket_number,
          DECODE(TO_CHAR(pocket_number),'1',NVL(given_p1_type,'504'),
                                        '2',NVL(given_p2_type,'504'),
                                        '3',NVL(given_p3_type,'504'),
                                        '4',NVL(given_p4_type,'504'),
                                        '5',NVL(given_p5_type,'504'),
                                        '6',NVL(given_p6_type,'504'),
                                        '7',NVL(given_p7_type,'504'),
                                        '8',NVL(given_p8_type,'504'),
                                        '504') theparttype,
          max_length,
          SYSDATE,-1,SYSDATE,-1,-1
  FROM reco_rstx_pockets;
END; -- add_pockets_for_day

--------------------------------------------------------------------------------
PROCEDURE add_pockets_for_day (given_calday_id IN number)
IS
BEGIN -- add_pockets_for_day
  add_pockets_for_day(given_calday_id,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL);
END; -- add_pockets_for_day

--------------------------------------------------------------------------------
-- proc_DefaultUserParams
PROCEDURE proc_DefaultUserParams
IS
BEGIN -- proc_DefaultUserParams
  DELETE FROM reco_rstx_userparam;
  
  INSERT INTO RECO_RSTX_USERPARAM
  (USERPARAM_ID,RAW_BAR_SIZE,MIN_CUT_ALLOWED,MAX_CUT_ALLOWED,
    SAFETY_DAYS_OUT,RARE_LENGTH_DAYS_OUT,LARGERBARS_NEAR_MACHINE,
    SHOW_CUTRPT_100INCRS,IGNORE_CURR_NP_INV,
    FIRST_DATE_OF_REQS,FIRST_DATE_OF_CUTTING,
    LAST_UPDATE_DATE,LAST_UPDATED_BY,CREATION_DATE,
    CREATED_BY,LAST_UPDATE_LOGIN)
  SELECT  reco_rstx_userparam_seq.nextval,
          48,6,38,10,5,'N','N','N',
          TO_DATE('01-SEP-2012','DD-MON-YYYY'),
          TO_DATE('15-SEP-2012','DD-MON-YYYY'),
          SYSDATE,-1,SYSDATE,-1,-1
  FROM dual;

  COMMIT;
END; -- proc_DefaultUserParams

--------------------------------------------------------------------------------
-- proc_DefaultOverwritePockets
PROCEDURE proc_DefaultOverwritePockets
IS
BEGIN -- proc_DefaultOverwritePockets
  DELETE FROM reco_rstx_pockets;
  
  INSERT INTO reco_rstx_pockets
    (pocket_id,pocket_number,storage_capacity,max_length,
      last_update_date,last_updated_by,creation_date,created_by,last_update_login)
  SELECT reco_rstx_pockets_seq.nextval,1,200,60,SYSDATE,-1,SYSDATE,-1,-1
  FROM dual;
  
  INSERT INTO reco_rstx_pockets
    (pocket_id,pocket_number,storage_capacity,max_length,
      last_update_date,last_updated_by,creation_date,created_by,last_update_login)
  SELECT reco_rstx_pockets_seq.nextval,2,200,60,SYSDATE,-1,SYSDATE,-1,-1
  FROM dual;
  
  INSERT INTO reco_rstx_pockets
    (pocket_id,pocket_number,storage_capacity,max_length,
      last_update_date,last_updated_by,creation_date,created_by,last_update_login)
  SELECT reco_rstx_pockets_seq.nextval,3,300,60,SYSDATE,-1,SYSDATE,-1,-1
  FROM dual;
  
  INSERT INTO reco_rstx_pockets
    (pocket_id,pocket_number,storage_capacity,max_length,
      last_update_date,last_updated_by,creation_date,created_by,last_update_login)
  SELECT reco_rstx_pockets_seq.nextval,4,400,60,SYSDATE,-1,SYSDATE,-1,-1
  FROM dual;
  
  INSERT INTO reco_rstx_pockets
    (pocket_id,pocket_number,storage_capacity,max_length,
      last_update_date,last_updated_by,creation_date,created_by,last_update_login)
  SELECT reco_rstx_pockets_seq.nextval,5,400,60,SYSDATE,-1,SYSDATE,-1,-1
  FROM dual;
  
  INSERT INTO reco_rstx_pockets
    (pocket_id,pocket_number,storage_capacity,max_length,
      last_update_date,last_updated_by,creation_date,created_by,last_update_login)
  SELECT reco_rstx_pockets_seq.nextval,6,300,60,SYSDATE,-1,SYSDATE,-1,-1
  FROM dual;
  
  INSERT INTO reco_rstx_pockets
    (pocket_id,pocket_number,storage_capacity,max_length,
      last_update_date,last_updated_by,creation_date,created_by,last_update_login)
  SELECT reco_rstx_pockets_seq.nextval,7,200,60,SYSDATE,-1,SYSDATE,-1,-1
  FROM dual;
  
  INSERT INTO reco_rstx_pockets
    (pocket_id,pocket_number,storage_capacity,max_length,
      last_update_date,last_updated_by,creation_date,created_by,last_update_login)
  SELECT reco_rstx_pockets_seq.nextval,8,200,60,SYSDATE,-1,SYSDATE,-1,-1
  FROM dual;
  
  COMMIT;
END; -- proc_DefaultOverwritePockets

--------------------------------------------------------------------------------
-- proc_DefaultOverwriteMtx
-- 
-- DSM - April 2013
-- The 4-piece and 5-piece cut schedule works flawlessly..
-- So the code is all good.
-- 
-- But business requirements (based on 2" rounding of cuts)
-- requires us to remove the 4-piece and 5-piece matrices.
-- (This is by design).
-- 
-- So everything WORKS for 4-piece and 5-piece matrixes,
-- but we do not make them available for cutting
-- 
-- To re-implement, find the code with label
-- -- APR2013: 4/5 PIECE CODE TO UNCOMMENT
-- -- APR2013: 4/5 PIECE CODE TO SWAP
-- -- APR2013: 4/5 PIECE CODE TO REMOVE
-- and then it will work again
PROCEDURE proc_DefaultOverwriteMtx
IS
  vn_Length1 number;
  vn_Length2 number;
  vn_Length3 number;
  vn_Length4 number;
  vn_Length5 number;
  
  vc_Type varchar2(10);
  
  vc_MaxBarLen number;
  
  PROCEDURE proc_AddIt( pi_1 IN number,
                        pi_2 IN number,
                        pi_3 IN number,
                        pi_4 IN number,
                        pi_5 IN number)
  IS
    vr_cutmtx reco_rstx_cutmtx%ROWTYPE;
  BEGIN
    
    DECLARE
      vn_QtyPieces number;
    BEGIN
      IF pi_1 IS NOT NULL
      AND pi_2 IS NOT NULL
      AND pi_3 IS NULL
      AND pi_4 IS NULL
      AND pi_5 IS NULL
      THEN vn_QtyPieces := 2;
      ELSIF pi_1 IS NOT NULL
      AND pi_2 IS NOT NULL
      AND pi_3 IS NOT NULL
      AND pi_4 IS NULL
      AND pi_5 IS NULL
      THEN vn_QtyPieces := 3;
      ELSIF pi_1 IS NOT NULL
      AND pi_2 IS NOT NULL
      AND pi_3 IS NOT NULL
      AND pi_4 IS NOT NULL
      AND pi_5 IS NULL
      THEN vn_QtyPieces := 4;
      ELSIF pi_1 IS NOT NULL
      AND pi_2 IS NOT NULL
      AND pi_3 IS NOT NULL
      AND pi_4 IS NOT NULL
      AND pi_5 IS NOT NULL
      THEN vn_QtyPieces := 5;
      END IF;
      
      SELECT reco_rstx_cutmtx_seq.nextval INTO vr_cutmtx.cutmtx_id FROM dual;
      
      vr_cutmtx.ptype := vc_Type;
      
      vr_cutmtx.qty_pieces_made := vn_QtyPieces;
    END;
    
    INSERT INTO reco_rstx_cutmtx
    (CUTMTX_ID,PTYPE,QTY_PIECES_MADE,
      LAST_UPDATE_DATE,LAST_UPDATED_BY,CREATION_DATE,
      CREATED_BY,LAST_UPDATE_LOGIN)
    VALUES
    (vr_cutmtx.cutmtx_id,vr_cutmtx.ptype,vr_cutmtx.qty_pieces_made,
      SYSDATE,-1,SYSDATE,-1,-1);
    
    IF vr_cutmtx.qty_pieces_made >= 1
    THEN
      INSERT INTO reco_rstx_cutpce
      (CUTPCE_ID,CUTMTX_ID,PIECE_NUMBER,UNIT_VOLUME,
        LAST_UPDATE_DATE,LAST_UPDATED_BY,CREATION_DATE,
        CREATED_BY,LAST_UPDATE_LOGIN)
      SELECT  reco_rstx_cutpce_seq.nextval,
              vr_cutmtx.cutmtx_id,1,pi_1,SYSDATE,-1,SYSDATE,-1,-1
      FROM dual;
    END IF;
    
    IF vr_cutmtx.qty_pieces_made >= 2
    THEN
      INSERT INTO reco_rstx_cutpce
      (CUTPCE_ID,CUTMTX_ID,PIECE_NUMBER,UNIT_VOLUME,
        LAST_UPDATE_DATE,LAST_UPDATED_BY,CREATION_DATE,
        CREATED_BY,LAST_UPDATE_LOGIN)
      SELECT  reco_rstx_cutpce_seq.nextval,
              vr_cutmtx.cutmtx_id,2,pi_2,SYSDATE,-1,SYSDATE,-1,-1
      FROM dual;
    END IF;
    
    IF vr_cutmtx.qty_pieces_made >= 3
    THEN
      INSERT INTO reco_rstx_cutpce
      (CUTPCE_ID,CUTMTX_ID,PIECE_NUMBER,UNIT_VOLUME,
        LAST_UPDATE_DATE,LAST_UPDATED_BY,CREATION_DATE,
        CREATED_BY,LAST_UPDATE_LOGIN)
      SELECT  reco_rstx_cutpce_seq.nextval,
              vr_cutmtx.cutmtx_id,3,pi_3,SYSDATE,-1,SYSDATE,-1,-1
      FROM dual;
    END IF;
    
    IF vr_cutmtx.qty_pieces_made >= 4
    THEN
      INSERT INTO reco_rstx_cutpce
      (CUTPCE_ID,CUTMTX_ID,PIECE_NUMBER,UNIT_VOLUME,
        LAST_UPDATE_DATE,LAST_UPDATED_BY,CREATION_DATE,
        CREATED_BY,LAST_UPDATE_LOGIN)
      SELECT  reco_rstx_cutpce_seq.nextval,
              vr_cutmtx.cutmtx_id,4,pi_4,SYSDATE,-1,SYSDATE,-1,-1
      FROM dual;
    END IF;
    
    IF vr_cutmtx.qty_pieces_made >= 5
    THEN
      INSERT INTO reco_rstx_cutpce
      (CUTPCE_ID,CUTMTX_ID,PIECE_NUMBER,UNIT_VOLUME,
        LAST_UPDATE_DATE,LAST_UPDATED_BY,CREATION_DATE,
        CREATED_BY,LAST_UPDATE_LOGIN)
      SELECT  reco_rstx_cutpce_seq.nextval,
              vr_cutmtx.cutmtx_id,5,pi_5,SYSDATE,-1,SYSDATE,-1,-1
      FROM dual;
    END IF;
  END;
  
  PROCEDURE proc_CombineIt(pi_GivenLength IN number)
  IS
  BEGIN
    -- don't forget 12x12x12x12 and 16x16x16 and 24x24
    -- which don't work in the matrix logic below
    IF pi_GivenLength = 24
    THEN proc_AddIt(24,24,NULL,NULL,NULL);
    ELSIF pi_GivenLength = 16
    THEN proc_AddIt(16,16,16,NULL,NULL);
    --elsif pi_GivenLength = 12
    --then proc_AddIt(12,12,12,12,null); -- APR2013: 4/5 PIECE CODE TO UNCOMMENT
    END IF;
    
    -- 2-piece total and 1 given -----------------------------------
    
    FOR vn_Length1 IN 3 .. 38
    LOOP
      IF vn_Length1 != pi_GivenLength
      THEN CONTINUE;
      END IF;
      
      FOR vn_Length2 IN 3 .. 38
      LOOP
        IF vn_Length2 = pi_GivenLength
        THEN CONTINUE;
        END IF;
        
        IF vn_Length1 + vn_Length2 != vc_MaxBarLen
        THEN CONTINUE;
        END IF;
        
        proc_AddIt(vn_Length1,vn_Length2,NULL,NULL,NULL);
      END LOOP; -- 2
    END LOOP; -- 1
    
    -- 3-piece total and 1 given -----------------------------------
    
    FOR vn_Length1 IN 3 .. 38
    LOOP
      IF vn_Length1 != pi_GivenLength
      THEN CONTINUE;
      END IF;
      
      FOR vn_Length2 IN 3 .. 38
      LOOP
        IF vn_Length2 = pi_GivenLength
        THEN CONTINUE;
        END IF;
        
        FOR vn_Length3 IN 3 .. 38
        LOOP
          IF vn_Length3 = pi_GivenLength
          THEN CONTINUE;
          END IF;
          
          IF vn_Length1 + vn_Length2 + vn_Length3 != vc_MaxBarLen
          THEN CONTINUE;
          END IF;
          
          proc_AddIt(vn_Length1,vn_Length2,vn_Length3,NULL,NULL);
        END LOOP; -- 3
      END LOOP; -- 2
    END LOOP; -- 1
    
    -- 3-piece total and 2 given -----------------------------------
    
    FOR vn_Length1 IN 3 .. 38
    LOOP
      IF vn_Length1 != pi_GivenLength
      THEN CONTINUE;
      END IF;
      
      FOR vn_Length2 IN 3 .. 38
      LOOP
        IF vn_Length2 != pi_GivenLength
        THEN CONTINUE;
        END IF;
        
        FOR vn_Length3 IN 3 .. 38
        LOOP
          IF vn_Length3 = pi_GivenLength
          THEN CONTINUE;
          END IF;
          
          IF vn_Length1 + vn_Length2 + vn_Length3 != vc_MaxBarLen
          THEN CONTINUE;
          END IF;
          
          proc_AddIt(vn_Length1,vn_Length2,vn_Length3,NULL,NULL);
        END LOOP; -- 3
      END LOOP; -- 2
    END LOOP; -- 1
    
--    -- 4-piece total and 1 given -----------------------------------
--    -- APR2013: 4/5 PIECE CODE TO UNCOMMENT
--    for vn_Length1 in 3 .. 38
--    loop
--      if vn_Length1 != pi_GivenLength
--      then continue;
--      end if;
--      
--      for vn_Length2 in 3 .. 38
--      loop
--        if vn_Length2 = pi_GivenLength
--        then continue;
--        end if;
--        
--        for vn_Length3 in 3 .. 38
--        loop
--          if vn_Length3 = pi_GivenLength
--          then continue;
--          end if;
--          
--          for vn_Length4 in 3 .. 38
--          loop
--            if vn_Length4 = pi_GivenLength
--            then continue;
--            end if;
--            
--            if vn_Length1 + vn_Length2 + vn_Length3 + vn_Length4 != vc_MaxBarLen
--            then continue;
--            end if;
--            
--            proc_AddIt(vn_Length1,vn_Length2,vn_Length3,vn_Length4,null);
--          end loop; -- 4
--        end loop; -- 3
--      end loop; -- 2
--    end loop; -- 1
    
--    -- 4-piece total and 2 given -----------------------------------
--    -- APR2013: 4/5 PIECE CODE TO UNCOMMENT
--    for vn_Length1 in 3 .. 38
--    loop
--      if vn_Length1 != pi_GivenLength
--      then continue;
--      end if;
--      
--      for vn_Length2 in 3 .. 38
--      loop
--        if vn_Length2 != pi_GivenLength
--        then continue;
--        end if;
--        
--        for vn_Length3 in 3 .. 38
--        loop
--          if vn_Length3 = pi_GivenLength
--          then continue;
--          end if;
--          
--          for vn_Length4 in 3 .. 38
--          loop
--            if vn_Length4 = pi_GivenLength
--            then continue;
--            end if;
--            
--            if vn_Length1 + vn_Length2 + vn_Length3 + vn_Length4 != vc_MaxBarLen
--            then continue;
--            end if;
--            
--            proc_AddIt(vn_Length1,vn_Length2,vn_Length3,vn_Length4,null);
--          end loop; -- 4
--        end loop; -- 3
--      end loop; -- 2
--    end loop; -- 1
    
--    -- 4-piece total and 3 given -----------------------------------
--    -- APR2013: 4/5 PIECE CODE TO UNCOMMENT
--    for vn_Length1 in 3 .. 38
--    loop
--      if vn_Length1 != pi_GivenLength
--      then continue;
--      end if;
--      
--      for vn_Length2 in 3 .. 38
--      loop
--        if vn_Length2 != pi_GivenLength
--        then continue;
--        end if;
--        
--        for vn_Length3 in 3 .. 38
--        loop
--          if vn_Length3 != pi_GivenLength
--          then continue;
--          end if;
--          
--          for vn_Length4 in 3 .. 38
--          loop
--            if vn_Length4 = pi_GivenLength
--            then continue;
--            end if;
--            
--            if vn_Length1 + vn_Length2 + vn_Length3 + vn_Length4 != vc_MaxBarLen
--            then continue;
--            end if;
--            
--            proc_AddIt(vn_Length1,vn_Length2,vn_Length3,vn_Length4,null);
--          end loop; -- 4
--        end loop; -- 3
--      end loop; -- 2
--    end loop; -- 1
  END;
  
BEGIN -- proc_DefaultOverwriteMtx
  
  DELETE FROM reco_rstx_run_placement;
  DELETE FROM reco_rstx_cutasgv2;
  DELETE FROM reco_rstx_cutovg;
  DELETE FROM reco_rstx_cutrun;
  DELETE FROM reco_rstx_cutpce;
  DELETE FROM reco_rstx_cutmtx;
  
  vc_Type := '504';
  vc_MaxBarLen := 48;
  proc_CombineIt(3);
  proc_CombineIt(4);
  proc_CombineIt(5);
  proc_CombineIt(6);
  proc_CombineIt(7);
  proc_CombineIt(8);
  proc_CombineIt(9);
  proc_CombineIt(10);
  proc_CombineIt(11);
  proc_CombineIt(12);
  proc_CombineIt(13);
  proc_CombineIt(14);
  proc_CombineIt(15);
  proc_CombineIt(16);
  proc_CombineIt(17);
  proc_CombineIt(18);
  proc_CombineIt(19);
  proc_CombineIt(20);
  proc_CombineIt(21);
  proc_CombineIt(22);
  proc_CombineIt(23);
  proc_CombineIt(24);
  proc_CombineIt(25);
  proc_CombineIt(26);
  proc_CombineIt(27);
  proc_CombineIt(28);
  proc_CombineIt(29);
  proc_CombineIt(30);
  proc_CombineIt(31);
  proc_CombineIt(32);
  proc_CombineIt(33);
  proc_CombineIt(34);
  proc_CombineIt(35);
  proc_CombineIt(36);
  proc_CombineIt(37);
  proc_CombineIt(38);
  
  vc_Type := '505';
  vc_MaxBarLen := 48;
  proc_CombineIt(3);
  proc_CombineIt(4);
  proc_CombineIt(5);
  proc_CombineIt(6);
  proc_CombineIt(7);
  proc_CombineIt(8);
  proc_CombineIt(9);
  proc_CombineIt(10);
  proc_CombineIt(11);
  proc_CombineIt(12);
  proc_CombineIt(13);
  proc_CombineIt(14);
  proc_CombineIt(15);
  proc_CombineIt(16);
  proc_CombineIt(17);
  proc_CombineIt(18);
  proc_CombineIt(19);
  proc_CombineIt(20);
  proc_CombineIt(21);
  proc_CombineIt(22);
  proc_CombineIt(23);
  proc_CombineIt(24);
  proc_CombineIt(25);
  proc_CombineIt(26);
  proc_CombineIt(27);
  proc_CombineIt(28);
  proc_CombineIt(29);
  proc_CombineIt(30);
  proc_CombineIt(31);
  proc_CombineIt(32);
  proc_CombineIt(33);
  proc_CombineIt(34);
  proc_CombineIt(35);
  proc_CombineIt(36);
  proc_CombineIt(37);
  proc_CombineIt(38);
  
  vc_Type := '506';
  vc_MaxBarLen := 48;
  proc_CombineIt(3);
  proc_CombineIt(4);
  proc_CombineIt(5);
  proc_CombineIt(6);
  proc_CombineIt(7);
  proc_CombineIt(8);
  proc_CombineIt(9);
  proc_CombineIt(10);
  proc_CombineIt(11);
  proc_CombineIt(12);
  proc_CombineIt(13);
  proc_CombineIt(14);
  proc_CombineIt(15);
  proc_CombineIt(16);
  proc_CombineIt(17);
  proc_CombineIt(18);
  proc_CombineIt(19);
  proc_CombineIt(20);
  proc_CombineIt(21);
  proc_CombineIt(22);
  proc_CombineIt(23);
  proc_CombineIt(24);
  proc_CombineIt(25);
  proc_CombineIt(26);
  proc_CombineIt(27);
  proc_CombineIt(28);
  proc_CombineIt(29);
  proc_CombineIt(30);
  proc_CombineIt(31);
  proc_CombineIt(32);
  proc_CombineIt(33);
  proc_CombineIt(34);
  proc_CombineIt(35);
  proc_CombineIt(36);
  proc_CombineIt(37);
  proc_CombineIt(38);
  
  vc_Type := '504';
  vc_MaxBarLen := 49;
  proc_CombineIt(3);
  proc_CombineIt(4);
  proc_CombineIt(5);
  proc_CombineIt(6);
  proc_CombineIt(7);
  proc_CombineIt(8);
  proc_CombineIt(9);
  proc_CombineIt(10);
  proc_CombineIt(11);
  proc_CombineIt(12);
  proc_CombineIt(13);
  proc_CombineIt(14);
  proc_CombineIt(15);
  proc_CombineIt(16);
  proc_CombineIt(17);
  proc_CombineIt(18);
  proc_CombineIt(19);
  proc_CombineIt(20);
  proc_CombineIt(21);
  proc_CombineIt(22);
  proc_CombineIt(23);
  proc_CombineIt(24);
  proc_CombineIt(25);
  proc_CombineIt(26);
  proc_CombineIt(27);
  proc_CombineIt(28);
  proc_CombineIt(29);
  proc_CombineIt(30);
  proc_CombineIt(31);
  proc_CombineIt(32);
  proc_CombineIt(33);
  proc_CombineIt(34);
  proc_CombineIt(35);
  proc_CombineIt(36);
  proc_CombineIt(37);
  proc_CombineIt(38);
  
  vc_Type := '505';
  vc_MaxBarLen := 49;
  proc_CombineIt(3);
  proc_CombineIt(4);
  proc_CombineIt(5);
  proc_CombineIt(6);
  proc_CombineIt(7);
  proc_CombineIt(8);
  proc_CombineIt(9);
  proc_CombineIt(10);
  proc_CombineIt(11);
  proc_CombineIt(12);
  proc_CombineIt(13);
  proc_CombineIt(14);
  proc_CombineIt(15);
  proc_CombineIt(16);
  proc_CombineIt(17);
  proc_CombineIt(18);
  proc_CombineIt(19);
  proc_CombineIt(20);
  proc_CombineIt(21);
  proc_CombineIt(22);
  proc_CombineIt(23);
  proc_CombineIt(24);
  proc_CombineIt(25);
  proc_CombineIt(26);
  proc_CombineIt(27);
  proc_CombineIt(28);
  proc_CombineIt(29);
  proc_CombineIt(30);
  proc_CombineIt(31);
  proc_CombineIt(32);
  proc_CombineIt(33);
  proc_CombineIt(34);
  proc_CombineIt(35);
  proc_CombineIt(36);
  proc_CombineIt(37);
  proc_CombineIt(38);
  
  vc_Type := '506';
  vc_MaxBarLen := 49;
  proc_CombineIt(3);
  proc_CombineIt(4);
  proc_CombineIt(5);
  proc_CombineIt(6);
  proc_CombineIt(7);
  proc_CombineIt(8);
  proc_CombineIt(9);
  proc_CombineIt(10);
  proc_CombineIt(11);
  proc_CombineIt(12);
  proc_CombineIt(13);
  proc_CombineIt(14);
  proc_CombineIt(15);
  proc_CombineIt(16);
  proc_CombineIt(17);
  proc_CombineIt(18);
  proc_CombineIt(19);
  proc_CombineIt(20);
  proc_CombineIt(21);
  proc_CombineIt(22);
  proc_CombineIt(23);
  proc_CombineIt(24);
  proc_CombineIt(25);
  proc_CombineIt(26);
  proc_CombineIt(27);
  proc_CombineIt(28);
  proc_CombineIt(29);
  proc_CombineIt(30);
  proc_CombineIt(31);
  proc_CombineIt(32);
  proc_CombineIt(33);
  proc_CombineIt(34);
  proc_CombineIt(35);
  proc_CombineIt(36);
  proc_CombineIt(37);
  proc_CombineIt(38);
  
  COMMIT;
END; -- proc_DefaultOverwriteMtx

--------------------------------------------------------------------------------
-- proc_DefaultOverwriteCalendar
PROCEDURE proc_DefaultOverwriteCalendar
IS
  vd_TmpDate date := TO_DATE('01-JAN-2012','DD-MON-YYYY');
  vn_TmpId number;
BEGIN -- proc_DefaultOverwriteCalendar
  
  DELETE FROM reco_rstx_run_placement;
  DELETE FROM reco_rstx_day_pkt_bin;
  DELETE FROM reco_rstx_day_pocket;
  DELETE FROM reco_rstx_calday;
  
  LOOP
    SELECT reco_rstx_calday_seq.nextval INTO vn_TmpId FROM dual;
    
    IF TO_CHAR(vd_TmpDate,'DY') IN ('SAT','SUN')
    THEN
      INSERT INTO reco_rstx_calday
        (calday_id,thedate,qty_bars_max,qty_bars_per_run,
          is_production_allowed,last_update_date,last_updated_by,
          creation_date,created_by,last_update_login)
      VALUES
        (vn_TmpId,vd_TmpDate,2000,100,'N',SYSDATE,-1,SYSDATE,-1,-1);
    ELSE
      INSERT INTO reco_rstx_calday
        (calday_id,thedate,qty_bars_max,qty_bars_per_run,
          is_production_allowed,last_update_date,last_updated_by,
          creation_date,created_by,last_update_login)
      VALUES
        (vn_TmpId,vd_TmpDate,2000,100,'Y',SYSDATE,-1,SYSDATE,-1,-1);
    END IF;
    
    add_pockets_for_day(vn_TmpId);
    
    vd_TmpDate := vd_TmpDate + 1;
    
    IF vd_TmpDate >= TO_DATE('01-JAN-2015','DD-MON-YYYY')
    THEN exit;
    END IF;
  END LOOP;
  
  COMMIT;
END; -- proc_DefaultOverwriteCalendar

--------------------------------------------------------------------------------
-- proc_DefaultOverwriteRareLen
PROCEDURE proc_DefaultOverwriteRareLen
IS
  vn_TmpId number;
BEGIN -- proc_DefaultOverwriteRareLen
  
  DELETE FROM reco_rstx_rarelength;
  
  SELECT reco_rstx_rarelength_seq.nextval INTO vn_TmpId FROM dual;
  INSERT INTO reco_rstx_rarelength (rarelength_id, unit_volume,
    last_update_date,last_updated_by,creation_date,created_by,last_update_login)
  VALUES (vn_TmpId,3,SYSDATE,-1,SYSDATE,-1,-1);
  
  SELECT reco_rstx_rarelength_seq.nextval INTO vn_TmpId FROM dual;
  INSERT INTO reco_rstx_rarelength (rarelength_id, unit_volume,
    last_update_date,last_updated_by,creation_date,created_by,last_update_login)
  VALUES (vn_TmpId,4,SYSDATE,-1,SYSDATE,-1,-1);
  
  SELECT reco_rstx_rarelength_seq.nextval INTO vn_TmpId FROM dual;
  INSERT INTO reco_rstx_rarelength (rarelength_id, unit_volume,
    last_update_date,last_updated_by,creation_date,created_by,last_update_login)
  VALUES (vn_TmpId,5,SYSDATE,-1,SYSDATE,-1,-1);
  
  SELECT reco_rstx_rarelength_seq.nextval INTO vn_TmpId FROM dual;
  INSERT INTO reco_rstx_rarelength (rarelength_id, unit_volume,
    last_update_date,last_updated_by,creation_date,created_by,last_update_login)
  VALUES (vn_TmpId,6,SYSDATE,-1,SYSDATE,-1,-1);
  
  SELECT reco_rstx_rarelength_seq.nextval INTO vn_TmpId FROM dual;
  INSERT INTO reco_rstx_rarelength (rarelength_id, unit_volume,
    last_update_date,last_updated_by,creation_date,created_by,last_update_login)
  VALUES (vn_TmpId,7,SYSDATE,-1,SYSDATE,-1,-1);
  
  SELECT reco_rstx_rarelength_seq.nextval INTO vn_TmpId FROM dual;
  INSERT INTO reco_rstx_rarelength (rarelength_id, unit_volume,
    last_update_date,last_updated_by,creation_date,created_by,last_update_login)
  VALUES (vn_TmpId,33,SYSDATE,-1,SYSDATE,-1,-1);
  
  SELECT reco_rstx_rarelength_seq.nextval INTO vn_TmpId FROM dual;
  INSERT INTO reco_rstx_rarelength (rarelength_id, unit_volume,
    last_update_date,last_updated_by,creation_date,created_by,last_update_login)
  VALUES (vn_TmpId,34,SYSDATE,-1,SYSDATE,-1,-1);
  
  SELECT reco_rstx_rarelength_seq.nextval INTO vn_TmpId FROM dual;
  INSERT INTO reco_rstx_rarelength (rarelength_id, unit_volume,
    last_update_date,last_updated_by,creation_date,created_by,last_update_login)
  VALUES (vn_TmpId,35,SYSDATE,-1,SYSDATE,-1,-1);
  
  SELECT reco_rstx_rarelength_seq.nextval INTO vn_TmpId FROM dual;
  INSERT INTO reco_rstx_rarelength (rarelength_id, unit_volume,
    last_update_date,last_updated_by,creation_date,created_by,last_update_login)
  VALUES (vn_TmpId,36,SYSDATE,-1,SYSDATE,-1,-1);
  
  SELECT reco_rstx_rarelength_seq.nextval INTO vn_TmpId FROM dual;
  INSERT INTO reco_rstx_rarelength (rarelength_id, unit_volume,
    last_update_date,last_updated_by,creation_date,created_by,last_update_login)
  VALUES (vn_TmpId,37,SYSDATE,-1,SYSDATE,-1,-1);
  
  SELECT reco_rstx_rarelength_seq.nextval INTO vn_TmpId FROM dual;
  INSERT INTO reco_rstx_rarelength (rarelength_id, unit_volume,
    last_update_date,last_updated_by,creation_date,created_by,last_update_login)
  VALUES (vn_TmpId,38,SYSDATE,-1,SYSDATE,-1,-1);
  
  COMMIT;
END; -- proc_DefaultOverwriteRareLen

--------------------------------------------------------------------------------
-- MatricesAreEqual
FUNCTION MatricesAreEqual (pi_Mtx1PceQty IN number,
                                pi_Mtx1Pce1 IN number,
                                pi_Mtx1Pce2 IN number,
                                pi_Mtx1Pce3 IN number,
                                pi_Mtx1Pce4 IN number,
                                pi_Mtx1Pce5 IN number,
                                pi_Mtx2PceQty IN number,
                                pi_Mtx2Pce1 IN number,
                                pi_Mtx2Pce2 IN number,
                                pi_Mtx2Pce3 IN number,
                                pi_Mtx2Pce4 IN number,
                                pi_Mtx2Pce5 IN number)
RETURN BOOLEAN
IS
  TYPE coll_Idxs IS TABLE OF number;
  oTheHistory coll_Idxs := coll_Idxs(); -- Initialize since not fetched
  nCtrHistory number;
  
  vn_CurrPceCtr number;
  vn_CurrPceLen number;
  
  vn_TestPceCtr number;
  vn_TestPceLen number;
  
  vn_HistCtrFound number;
BEGIN -- MatricesAreEqual
  
  IF pi_Mtx1PceQty != pi_Mtx2PceQty
  THEN RETURN FALSE;
  END IF;
  
  FOR vn_CurrPceCtr IN 1 .. pi_Mtx1PceQty
  LOOP
    IF vn_CurrPceCtr = 1 THEN vn_CurrPceLen := pi_Mtx1Pce1;
    ELSIF vn_CurrPceCtr = 2 THEN vn_CurrPceLen := pi_Mtx1Pce2;
    ELSIF vn_CurrPceCtr = 3 THEN vn_CurrPceLen := pi_Mtx1Pce3;
    ELSIF vn_CurrPceCtr = 4 THEN vn_CurrPceLen := pi_Mtx1Pce4;
    ELSIF vn_CurrPceCtr = 5 THEN vn_CurrPceLen := pi_Mtx1Pce5;
    END IF;
    
    FOR vn_TestPceCtr IN 1 .. pi_Mtx2PceQty
    LOOP
      IF vn_TestPceCtr = 1 THEN vn_TestPceLen := pi_Mtx2Pce1;
      ELSIF vn_TestPceCtr = 2 THEN vn_TestPceLen := pi_Mtx2Pce2;
      ELSIF vn_TestPceCtr = 3 THEN vn_TestPceLen := pi_Mtx2Pce3;
      ELSIF vn_TestPceCtr = 4 THEN vn_TestPceLen := pi_Mtx2Pce4;
      ELSIF vn_TestPceCtr = 5 THEN vn_TestPceLen := pi_Mtx2Pce5;
      END IF;
      
      IF vn_CurrPceLen = vn_TestPceLen
      THEN
        vn_HistCtrFound := NULL;
        
        FOR nCtrHistory IN 1 .. oTheHistory.count
        LOOP
          IF oTheHistory(nCtrHistory) = vn_TestPceCtr
          THEN vn_HistCtrFound := nCtrHistory; exit;
          END IF;
        END LOOP;
        
        IF vn_HistCtrFound IS NULL
        THEN
          oTheHistory.extend(1);
          oTheHistory(oTheHistory.count) := vn_TestPceCtr;
          exit;
        END IF;
      END IF;
    END LOOP;
    
    IF oTheHistory.count != vn_CurrPceCtr
    THEN RETURN FALSE;
    END IF;
  END LOOP;
  
  RETURN TRUE;
END; -- MatricesAreEqual

--------------------------------------------------------------------------------
-- SortMatrixPieces
PROCEDURE SortMatrixPieces( pi_PceQty IN number,
                            pi_Pce1 IN number,
                            pi_Pce2 IN number,
                            pi_Pce3 IN number,
                            pi_Pce4 IN number,
                            pi_Pce5 IN number,
                            pi_SortAsc IN BOOLEAN,
                            pi_SortDesc IN BOOLEAN,
                            po_P1 OUT number,
                            po_P2 OUT number,
                            po_P3 OUT number,
                            po_P4 OUT number,
                            po_P5 OUT number)
IS
  TYPE coll_nums IS TABLE OF number;
  oTheBuffer coll_nums := coll_nums(); -- Initialize since not fetched
  nCtrBuffer number;
  
  vn_TempSwap number;
  
  vn_OutCtr number;
  vn_InCtr number;
BEGIN -- SortMatrixPieces
  
  IF pi_PceQty = 1
  THEN po_P1 := pi_Pce1; RETURN;
  END IF;
  
  --if pi_SortAsc is null and pi_SortDesc is null
  --or pi_SortAsc = pi_SortDesc -- CONTINUE HERE catch-all for caller error
  --then
  --  pi_SortAsc := true;
  --  pi_SortDesc := false;
  --end if;
  
  oTheBuffer.extend(pi_PceQty);
  FOR nCtrBuffer IN 1 .. oTheBuffer.count
  LOOP
    IF nCtrBuffer = 1 THEN oTheBuffer(nCtrBuffer) := pi_Pce1;
    ELSIF nCtrBuffer = 2 THEN oTheBuffer(nCtrBuffer) := pi_Pce2;
    ELSIF nCtrBuffer = 3 THEN oTheBuffer(nCtrBuffer) := pi_Pce3;
    ELSIF nCtrBuffer = 4 THEN oTheBuffer(nCtrBuffer) := pi_Pce4;
    ELSIF nCtrBuffer = 5 THEN oTheBuffer(nCtrBuffer) := pi_Pce5;
    END IF;
  END LOOP;
  
  FOR vn_OutCtr IN 1 .. pi_PceQty
  LOOP
    FOR vn_InCtr IN 2 .. pi_PceQty
    LOOP
      IF ( pi_SortAsc = TRUE AND oTheBuffer(vn_InCtr-1) > oTheBuffer(vn_InCtr) )
      OR ( pi_SortDesc = TRUE AND oTheBuffer(vn_InCtr-1) < oTheBuffer(vn_InCtr) )
      THEN
        vn_TempSwap := oTheBuffer(vn_InCtr);
        oTheBuffer(vn_InCtr) := oTheBuffer(vn_InCtr-1);
        oTheBuffer(vn_InCtr-1) := vn_TempSwap;
      END IF;
    END LOOP;
  END LOOP;
  
  po_P1 := 0; IF oTheBuffer.count >= 1 THEN po_P1 := oTheBuffer(1); END IF;
  po_P2 := 0; IF oTheBuffer.count >= 2 THEN po_P2 := oTheBuffer(2); END IF;
  po_P3 := 0; IF oTheBuffer.count >= 3 THEN po_P3 := oTheBuffer(3); END IF;
  po_P4 := 0; IF oTheBuffer.count >= 4 THEN po_P4 := oTheBuffer(4); END IF;
  po_P5 := 0; IF oTheBuffer.count >= 5 THEN po_P5 := oTheBuffer(5); END IF;
END; -- SortMatrixPieces

--------------------------------------------------------------------------------
-- SortMatrixPieces
PROCEDURE SortMatrixPieces(pi_PceQty IN number,
                                pi_Pce1 IN number,
                                pi_Pce2 IN number,
                                pi_Pce3 IN number,
                                pi_Pce4 IN number,
                                pi_Pce5 IN number,
                                po_P1 OUT number,
                                po_P2 OUT number,
                                po_P3 OUT number,
                                po_P4 OUT number,
                                po_P5 OUT number)
IS
BEGIN
  SortMatrixPieces(pi_PceQty,pi_Pce1,pi_Pce2,pi_Pce3,pi_Pce4,pi_Pce5,
                        TRUE,FALSE,po_P1,po_P2,po_P3,po_P4,po_P5);
END;

--------------------------------------------------------------------------------
-- clear_existing_reqsandplans
-- 
-- Flush the whole calculation system (not the history)
-- 
-- Understand that the History includes the current run,
-- so it is okay to flush the current system if desired
-- because everything else should be working of the recent history tables
PROCEDURE clear_existing_reqsandplans
IS
BEGIN -- clear_existing_reqsandplans
  DELETE FROM reco_rstx_galvreqcalc;
  DELETE FROM reco_rstx_galvreq;
  DELETE FROM reco_rstx_punreqcalc;
  DELETE FROM reco_rstx_punovg;
  DELETE FROM reco_rstx_punasg;
  DELETE FROM reco_rstx_punrun;
  DELETE FROM reco_rstx_punreq;
  DELETE FROM reco_rstx_cutreqcalc;
  DELETE FROM reco_rstx_sortedcut; -- should also be cleared in its loop
  DELETE FROM reco_rstx_cutcalc_future; -- should also be cleared in its loop
  DELETE FROM reco_rstx_cutcalc_daily; -- should also be cleared in its loop
  DELETE FROM reco_rstx_cutmtx_lenpunmap;
  DELETE FROM reco_rstx_cutovg;
  DELETE FROM reco_rstx_cutasgv2;
  DELETE FROM reco_rstx_run_placement;
  DELETE FROM reco_rstx_day_pkt_bin;
  DELETE FROM reco_rstx_cutrun;
  DELETE FROM reco_rstx_cutreqv2;
  DELETE FROM reco_rstx_originvqty;
END; -- clear_existing_reqsandplans

--------------------------------------------------------------------------------
-- validate_and_count_inv
-- 
-- NOTE
-- This function does a few things
-- : Setup RSTX inventory totals into reco_rstx_originvqty table
-- : If a part is "bad" in inventory, then it will still get an entry into
--   the reco_rstx_originvqty table. However, the inventory_item_id value
--   for that part will be set to null in the reco_rstx_originvqty table
-- : Check if inventory parts are missing (e.g. is the S504G12 part defined?)
-- : Check if inventory parts are active
-- : Check if inventory parts are in the correct category
-- : Check if NoPunBlk / SinPunBlk / DouPunBlk / SinPunGalv / DouPunGalv exist
-- : Check if a cut matrix exists for the part
-- : Check if parts have correct category set
-- : Check if parts have a cut matrix available
-- 
-- NOTE
-- The 504 parttype has stricter requirements than other part types
-- 
-- NOTE
-- This system already supports any parttype !!!
-- 504,506,ABCDEF are all supported currently.
-- But for the part to work appropriately, then the parts must be
-- defined properly in Oracle... which is purchasing's responsibility
-- 
-- PRE-CONDITIONS
-- : The 504 parttype should be setup pretty good in Oracle,
--   otherwise we will fail this whole process until they fix it
-- 
-- POST-CONDITIONS
-- : If there are significant problems with anything, then return error msg
-- : If there are no significant problems, then return 'DONE'
-- : If there are not significant problems:
--   : Function will return 'DONE'
--   : The reco_rstx_originvqty table is filled with relevant parts
--   : Some values in reco_rstx_originvqty may/may not have inventory_item_id
-- : If function completes, then you can make these assumptions about the
--   data in the reco_rstx_originvqty table
--   >> When you examine a part, then there are really 7 records.
--   >> For example, the part with parttype'504' and length'18' will have
--   >> these part records
--      : NU504B18
--      : SM504B18
--      : N504B18
--      : S504B18
--      : D504B18
--      : S504G18
--      : D504B18
--   >> For any part, all 7 of these records will exist, regardless of
--   >> how properly the part is setup in inventory / etc ...
-- : If function completes, then you can make these assumptions about the
--   data in the reco_rstx_originvqty table
--   The inventory item can be null for some parts.
--   There are 4 cases when a row in reco_rstx_originvqty will have a
--   null value for inventory_item_id
--   1) Case: The entire partTYPE has inventory_item_id of null
--            e.g. NU506B10 null, SM506B10 null, N506B10 null,
--                 S506B10 null, D506B10 null, S506G10 null, D506G10 null
--                 ...
--                 NU506B11 null, SM506B11 null, N506B11 null,
--                 S506B11 null, D506B11 null, S506G11 null, D506G11 null
--                 ...
--                 12, 13 etc ...
--      Reason: There is some critical issue with that parttype, so we
--              invalidate the whole parttype by setting inventory_item_id
--              to null value for all the parts
--   2) Case: Some parts within the parttype are null
--            e.g. For the 504 parts, then is parts have null InvItemId
--                 NU504B03 null, SM504B03 null, N504B03 null,
--                 S504B03 null, D504B03 null, S504G03 null, D504G03 null
--                 but all the other parts for 504 are okay.
--                 So only some lengths within 504 have null invItemId
--      Reason: Some parts have inventory issues, but the parts are not
--              important enough to disable all the partTYPE pieces.
--              In this example above, the 3' bar may not ever be used
--              in most cases, so we only invalidate the 3' bar pieces
--   3) Case: Some parts have only the RawStl version with null InvItemId
--            e.g. NU504B10 null, SM504B10 null,
--                 but the other N504B10 and S504B10 etc ... are okay
--      Reason: Purchasing does not define RawStl pieces for all the lengths,
--              and only do it when demanded. So we need to ensure that a
--              a part works properly, even if SM504B10 is missing
--   4) Case: All the parts for a parttype have inventory_item_id set
--            e.g. Inventory is setup optimally !!
FUNCTION validate_and_count_inv ( pi_first_date_of_reqs IN date,
                                  pi_min_cut_allowed IN number,
                                  pi_max_cut_allowed IN number)
RETURN VARCHAR2
IS
  TYPE coll_PartTypes IS TABLE OF apps.mtl_system_items_b.segment1%TYPE;
  
  oAllPartTypes coll_PartTypes; -- Fetched, so don't initialize
  
  oDemandedPartTypes coll_PartTypes := coll_PartTypes();
                                            -- Initialize since not fetched
BEGIN -- validate_and_count_inv
  
  ----------
  -- Determine which part types exist in inventory
  
  SELECT  DISTINCT
          CASE
          WHEN mic.category_set_id = nCSetR
          THEN SUBSTR(msib.segment1,3,INSTR(msib.segment1,'B',-1,1) - 3)
          WHEN mic.category_set_id = nCSetG
          THEN SUBSTR(msib.segment1,2,INSTR(msib.segment1,'G',-1,1) - 2)
          ELSE SUBSTR(msib.segment1,2,INSTR(msib.segment1,'B',-1,1) - 2)
          END
  BULK COLLECT INTO oAllPartTypes
  FROM  apps.mtl_system_items_b_kfv msib,
        apps.mtl_item_categories mic
  WHERE   msib.inventory_item_id = mic.inventory_item_id AND msib.organization_id = 0 AND mic.organizatioN_id = 0 
  AND     mic.category_set_id IN (nCSetN,nCSetB,nCSetG,nCSetR)
  AND     msib.inventory_item_status_code = 'Active'
  ORDER BY  CASE
            WHEN mic.category_set_id = nCSetR
            THEN SUBSTR(msib.segment1,3,INSTR(msib.segment1,'B',-1,1) - 3)
            WHEN mic.category_set_id = nCSetG
            THEN SUBSTR(msib.segment1,2,INSTR(msib.segment1,'G',-1,1) - 2)
            ELSE SUBSTR(msib.segment1,2,INSTR(msib.segment1,'B',-1,1) - 2)
            END;
  
  ----------
  -- Determine which existing part types are actually used in shipments
  
  FOR nCtrAllPartTypes IN 1 .. oAllPartTypes.count
  LOOP
    DECLARE
      vc_TmpChar varchar2(1);
    BEGIN
      SELECT 'Y'
      INTO vc_TmpChar
      FROM  reco_truck rs,
            reco_truckstop_parts rsp,
            apps.mtl_system_items_b_kfv msib,
            apps.mtl_item_categories mic
      WHERE   rs.truck_id = rsp.stop_truck_id
      AND     rsp.part_id = msib.inventory_item_id
      AND     msib.inventory_item_id = mic.inventory_item_id AND msib.organization_id = 0
      AND     rs.truck_status IN ('A','H','B')
      AND     rsp.orig_subinventory_code IN ('RSTX')
      AND     NVL(rsp.quantity,0) > 0
      AND     rs.truck_date >= pi_first_date_of_reqs
      AND     (
                ( mic.category_set_id = nCSetR
                  AND
                  SUBSTR(msib.segment1,3,INSTR(msib.segment1,'B',-1,1) - 3)
                    = oAllPartTypes(nCtrAllPartTypes) )
                OR
                ( mic.category_set_id = nCSetG
                  AND
                  SUBSTR(msib.segment1,2,INSTR(msib.segment1,'G',-1,1) - 2)
                    = oAllPartTypes(nCtrAllPartTypes) )
                OR
                ( mic.category_set_id = nCSetB
                  AND
                  SUBSTR(msib.segment1,2,INSTR(msib.segment1,'B',-1,1) - 2)
                    = oAllPartTypes(nCtrAllPartTypes) )
                OR
                ( mic.category_set_id = nCSetN
                  AND
                  SUBSTR(msib.segment1,2,INSTR(msib.segment1,'B',-1,1) - 2)
                    = oAllPartTypes(nCtrAllPartTypes) )
              );
      
      oDemandedPartTypes.extend(1);
      oDemandedPartTypes(oDemandedPartTypes.count) :=
                oAllPartTypes(nCtrAllPartTypes);
    EXCEPTION
      WHEN NO_DATA_FOUND
      THEN CONTINUE;
      WHEN TOO_MANY_ROWS
      THEN
        oDemandedPartTypes.extend(1);
        oDemandedPartTypes(oDemandedPartTypes.count) :=
                  oAllPartTypes(nCtrAllPartTypes);
      WHEN others
      THEN RETURN 'Internal Error 2040 - Unknown Error. Contact MIS';
    END;
  END LOOP;
  
  ----------
  -- Populate reco_rstx_originvqty
  
  DELETE FROM reco_rstx_originvqty;
  
  ----------
  -- Add to reco_rstx_originvqty - ignore inventory/mtl_system_items_b for now
  
  DECLARE
    vc_TmpCharLen varchar2(2);
  BEGIN
    FOR nPartTypeCtr IN 1 .. oDemandedPartTypes.count
    LOOP
      FOR nCtrLength IN 1 .. 47
      LOOP
        vc_TmpCharLen := TO_CHAR(nCtrLength);
        IF nCtrLength < 10
        THEN vc_TmpCharLen := '0'||TO_CHAR(nCtrLength);
        END IF;
        
        INSERT INTO reco_rstx_originvqty
        (originvqty_id,inventory_item_id,quantity,actual_attribute4,
          segment1,category_set_id,thepunch,thetype,thecoat,numlength,
          charlength,min_minmax_quantity,max_minmax_quantity,
          last_update_date,last_updated_by,
          creation_date,created_by,last_update_login)
        ( SELECT  reco_rstx_originvqty_seq.nextval,
                  NULL,0,NULL,
                  'NU'||oDemandedPartTypes(nPartTypeCtr)||'B'||vc_TmpCharLen,
                  nCSetR,'NU',oDemandedPartTypes(nPartTypeCtr),
                  'B',nCtrLength,vc_TmpCharLen,NULL,NULL,
                  SYSDATE,-1,SYSDATE,-1,-1 FROM dual);
        
        INSERT INTO reco_rstx_originvqty
        (originvqty_id,inventory_item_id,quantity,actual_attribute4,
          segment1,category_set_id,thepunch,thetype,thecoat,numlength,
          charlength,min_minmax_quantity,max_minmax_quantity,
          last_update_date,last_updated_by,
          creation_date,created_by,last_update_login)
        ( SELECT  reco_rstx_originvqty_seq.nextval,
                  NULL,0,NULL,
                  'SM'||oDemandedPartTypes(nPartTypeCtr)||'B'||vc_TmpCharLen,
                  nCSetR,'SM',oDemandedPartTypes(nPartTypeCtr),
                  'B',nCtrLength,vc_TmpCharLen,NULL,NULL,
                  SYSDATE,-1,SYSDATE,-1,-1 FROM dual);
        
        INSERT INTO reco_rstx_originvqty
        (originvqty_id,inventory_item_id,quantity,actual_attribute4,
          segment1,category_set_id,thepunch,thetype,thecoat,numlength,
          charlength,min_minmax_quantity,max_minmax_quantity,
          last_update_date,last_updated_by,
          creation_date,created_by,last_update_login)
        ( SELECT  reco_rstx_originvqty_seq.nextval,
                  NULL,0,NULL,
                  'N'||oDemandedPartTypes(nPartTypeCtr)||'B'||vc_TmpCharLen,
                  nCSetN,'N',oDemandedPartTypes(nPartTypeCtr),
                  'B',nCtrLength,vc_TmpCharLen,NULL,NULL,
                  SYSDATE,-1,SYSDATE,-1,-1 FROM dual);
        
        INSERT INTO reco_rstx_originvqty
        (originvqty_id,inventory_item_id,quantity,actual_attribute4,
          segment1,category_set_id,thepunch,thetype,thecoat,numlength,
          charlength,min_minmax_quantity,max_minmax_quantity,
          last_update_date,last_updated_by,
          creation_date,created_by,last_update_login)
        ( SELECT  reco_rstx_originvqty_seq.nextval,
                  NULL,0,NULL,
                  'S'||oDemandedPartTypes(nPartTypeCtr)||'B'||vc_TmpCharLen,
                  nCSetB,'S',oDemandedPartTypes(nPartTypeCtr),
                  'B',nCtrLength,vc_TmpCharLen,NULL,NULL,
                  SYSDATE,-1,SYSDATE,-1,-1 FROM dual);
        
        INSERT INTO reco_rstx_originvqty
        (originvqty_id,inventory_item_id,quantity,actual_attribute4,
          segment1,category_set_id,thepunch,thetype,thecoat,numlength,
          charlength,min_minmax_quantity,max_minmax_quantity,
          last_update_date,last_updated_by,
          creation_date,created_by,last_update_login)
        ( SELECT  reco_rstx_originvqty_seq.nextval,
                  NULL,0,NULL,
                  'D'||oDemandedPartTypes(nPartTypeCtr)||'B'||vc_TmpCharLen,
                  nCSetB,'D',oDemandedPartTypes(nPartTypeCtr),
                  'B',nCtrLength,vc_TmpCharLen,NULL,NULL,
                  SYSDATE,-1,SYSDATE,-1,-1 FROM dual);
        
        INSERT INTO reco_rstx_originvqty
        (originvqty_id,inventory_item_id,quantity,actual_attribute4,
          segment1,category_set_id,thepunch,thetype,thecoat,numlength,
          charlength,min_minmax_quantity,max_minmax_quantity,
          last_update_date,last_updated_by,
          creation_date,created_by,last_update_login)
        ( SELECT  reco_rstx_originvqty_seq.nextval,
                  NULL,0,NULL,
                  'S'||oDemandedPartTypes(nPartTypeCtr)||'G'||vc_TmpCharLen,
                  nCSetG,'S',oDemandedPartTypes(nPartTypeCtr),
                  'G',nCtrLength,vc_TmpCharLen,NULL,NULL,
                  SYSDATE,-1,SYSDATE,-1,-1 FROM dual);
        
        INSERT INTO reco_rstx_originvqty
        (originvqty_id,inventory_item_id,quantity,actual_attribute4,
          segment1,category_set_id,thepunch,thetype,thecoat,numlength,
          charlength,min_minmax_quantity,max_minmax_quantity,
          last_update_date,last_updated_by,
          creation_date,created_by,last_update_login)
        ( SELECT  reco_rstx_originvqty_seq.nextval,
                  NULL,0,NULL,
                  'D'||oDemandedPartTypes(nPartTypeCtr)||'G'||vc_TmpCharLen,
                  nCSetG,'D',oDemandedPartTypes(nPartTypeCtr),
                  'G',nCtrLength,vc_TmpCharLen,NULL,NULL,
                  SYSDATE,-1,SYSDATE,-1,-1 FROM dual);
      END LOOP;
      
      INSERT INTO reco_rstx_originvqty
      (originvqty_id,inventory_item_id,quantity,actual_attribute4,
        segment1,category_set_id,thepunch,thetype,thecoat,numlength,
        charlength,min_minmax_quantity,max_minmax_quantity,
        last_update_date,last_updated_by,
        creation_date,created_by,last_update_login)
      ( SELECT  reco_rstx_originvqty_seq.nextval,
                NULL,0,NULL,
                'NU'||oDemandedPartTypes(nPartTypeCtr)||'B48',
                nCSetR,'NU',oDemandedPartTypes(nPartTypeCtr),
                'B',48,'48',NULL,NULL,
                SYSDATE,-1,SYSDATE,-1,-1 FROM dual);
      
      INSERT INTO reco_rstx_originvqty
      (originvqty_id,inventory_item_id,quantity,actual_attribute4,
        segment1,category_set_id,thepunch,thetype,thecoat,numlength,
        charlength,min_minmax_quantity,max_minmax_quantity,
        last_update_date,last_updated_by,
        creation_date,created_by,last_update_login)
      ( SELECT  reco_rstx_originvqty_seq.nextval,
                NULL,0,NULL,
                'NU'||oDemandedPartTypes(nPartTypeCtr)||'B49',
                nCSetR,'NU',oDemandedPartTypes(nPartTypeCtr),
                'B',48,'48',NULL,NULL,
                SYSDATE,-1,SYSDATE,-1,-1 FROM dual);
      
      INSERT INTO reco_rstx_originvqty
      (originvqty_id,inventory_item_id,quantity,actual_attribute4,
        segment1,category_set_id,thepunch,thetype,thecoat,numlength,
        charlength,min_minmax_quantity,max_minmax_quantity,
        last_update_date,last_updated_by,
        creation_date,created_by,last_update_login)
      ( SELECT  reco_rstx_originvqty_seq.nextval,
                NULL,0,NULL,
                'SM'||oDemandedPartTypes(nPartTypeCtr)||'B48',
                nCSetR,'SM',oDemandedPartTypes(nPartTypeCtr),
                'B',48,'48',NULL,NULL,
                SYSDATE,-1,SYSDATE,-1,-1 FROM dual);
      
      INSERT INTO reco_rstx_originvqty
      (originvqty_id,inventory_item_id,quantity,actual_attribute4,
        segment1,category_set_id,thepunch,thetype,thecoat,numlength,
        charlength,min_minmax_quantity,max_minmax_quantity,
        last_update_date,last_updated_by,
        creation_date,created_by,last_update_login)
      ( SELECT  reco_rstx_originvqty_seq.nextval,
                NULL,0,NULL,
                'SM'||oDemandedPartTypes(nPartTypeCtr)||'B49',
                nCSetR,'SM',oDemandedPartTypes(nPartTypeCtr),
                'B',48,'48',NULL,NULL,
                SYSDATE,-1,SYSDATE,-1,-1 FROM dual);
    END LOOP;
  END;
  
  ----------
  -- Make sure inventory doesn't have duplicate parts
  
  DECLARE
    vc_TmpPartName apps.mtl_system_items_b.segment1%TYPE;
  BEGIN
    SELECT segment1 INTO vc_TmpPartName
    FROM
    (
      SELECT ROWNUM therownum, segment1
      FROM
      (
        SELECT roiq.segment1, COUNT(*) totall
        FROM reco_rstx_originvqty roiq, apps.mtl_system_items_b_kfv msib
        WHERE roiq.segment1 = msib.segment1 AND msib.organization_id = 0
        AND msib.inventory_item_status_code = 'Active'
        GROUP BY roiq.segment1
        HAVING COUNT(*) > 1
        ORDER BY roiq.segment1
      )
    )
    WHERE therownum = 1;
    
    RETURN 'Internal Error 2044 - Duplicate part '||
            vc_TmpPartName||' in inventory. - Contact Purchasing.';
  EXCEPTION
    WHEN NO_DATA_FOUND THEN NULL;
  END;
  
  ----------
  -- Update reco_rstx_originvqty - set quantity based on part name
  -- (do not use inventory_item_id for this step)
  -- 
  -- Remember that the INVENTORY_ITEM_IDs are still NULL at this point,
  -- so do not use any inventory_item_id for linkage
  -- 
  -- CONTINUE HERE -- CONTINUE HERE -- CONTINUE HERE -- CONTINUE HERE
  -- Is this dangerous?
  -- 
  -- Should this code be moved AFTER we verify the part / inventory_item_id ??
  
  DECLARE
    CURSOR cur_InvPartQtys
    IS
      SELECT roiq.segment1, msib.inventory_item_id, roiq.quantity
      FROM reco_rstx_originvqty roiq, apps.mtl_system_items_b_kfv msib
      WHERE roiq.segment1 = msib.segment1 AND msib.organization_id = 0
      AND EXISTS (SELECT 'Y'
                  FROM apps.mtl_onhand_quantities_detail moqd
                  WHERE moqd.subinventory_code = 'RSTX'
                  AND moqd.inventory_item_id = msib.inventory_item_id)
      FOR UPDATE OF roiq.quantity;
    
    vn_TmpInvQty number;
  BEGIN
    FOR rec_InvPartQtys IN cur_InvPartQtys
    LOOP
      SELECT SUM(transaction_quantity) INTO vn_TmpInvQty
      FROM apps.mtl_onhand_quantities_detail
      WHERE subinventory_code = 'RSTX'
      AND inventory_item_id = rec_InvPartQtys.inventory_item_id;
      
      UPDATE reco_rstx_originvqty
      set quantity = vn_TmpInvQty
      WHERE CURRENT OF cur_InvPartQtys;
    END LOOP;
  END;
  
  ----------
  -- Update reco_rstx_originvqty - set actual_attribute4 based on part name
  -- (do not use inventory_item_id for this step)
  
  DECLARE
    CURSOR cur_InvPartAttr
    IS
      SELECT  roiq.segment1,
              roiq.actual_attribute4,
              msib.attribute4
      FROM  reco_rstx_originvqty roiq,
            apps.mtl_system_items_b_kfv msib
      WHERE   roiq.segment1 = msib.segment1 AND msib.organization_id = 0 
      FOR UPDATE OF roiq.actual_attribute4;
    
    vc_TmpAttr4 apps.mtl_system_items_b.attribute4%TYPE;
  BEGIN
    FOR rec_InvPartAttr IN cur_InvPartAttr
    LOOP
      vc_TmpAttr4 := rec_InvPartAttr.attribute4;
      UPDATE reco_rstx_originvqty
      set actual_attribute4 = vc_TmpAttr4
      WHERE CURRENT OF cur_InvPartAttr;
    END LOOP;
  END;
  
  ----------
  -- Update reco_rstx_originvqty - set minmax quantities based on part name
  -- (do not use inventory_item_id for this step)
  
  DECLARE
    CURSOR cur_InvPartAttr
    IS
      SELECT  roiq.segment1,
              roiq.min_minmax_quantity,
              roiq.max_minmax_quantity,
              msib.min_minmax_quantity msib_min_qty,
              msib.max_minmax_quantity msib_max_qty
      FROM  reco_rstx_originvqty roiq,
            apps.mtl_system_items_b_kfv msib
      WHERE   roiq.segment1 = msib.segment1 AND msib.organization_id = 0
      FOR UPDATE OF roiq.min_minmax_quantity,
                    roiq.max_minmax_quantity;
    
    vn_TmpMin apps.mtl_system_items_b_kfv.min_minmax_quantity%TYPE;
    vn_TmpMax apps.mtl_system_items_b_kfv.max_minmax_quantity%TYPE;
  BEGIN
    FOR rec_InvPartAttr IN cur_InvPartAttr
    LOOP
      vn_TmpMin := rec_InvPartAttr.msib_min_qty;
      vn_TmpMax := rec_InvPartAttr.msib_max_qty;
      UPDATE reco_rstx_originvqty
      set min_minmax_quantity = vn_TmpMin,
          max_minmax_quantity = vn_TmpMax
      WHERE CURRENT OF cur_InvPartAttr;
    END LOOP;
  END;
  
  ----------
  -- Update reco_rstx_originvqty - update values for inventory_item_id
  -- 
  -- If a part is corrupt in inventory,
  -- then there are 3 actions we can do:
  -- Option #1: blank out the inventory_item_id only for the PartType/Len
  --           (Example: if S504G05 is bad in inventory, then we
  --                     update all X504X05 parts to NULL inventory_item_id)
  -- Option #2: wipe all the inventory_item_ids for that whole PartType
  --           (Example: if S504B12 is bad in inventory, then we
  --                     update ALL X504XYZ parts to set NULL for
  --                     inventory_item_id, which fails the whole 504 parttype)
  -- Option #3: return an error message (fail the whole cutsch refresh program)
  -- 
  -- Also note that may succeed for one part, but the RawStl for
  -- that part may be invalid (RawStl may still have null inventory_item_id)
  -- This is okay, because Purchasing does not define rawsteel very often
  -- so we need to support parts that do not have raw-steel equivalent
  
  DECLARE
    
    FUNCTION GetAndVerifyInvPart (pi_GivenPartName IN varchar2,
                                  pi_GivenPartCatSet IN number,
                                  pi_GivenPartLength IN number,
                                  pi_GivenPartType IN varchar2,
                                  po_OutIsSet OUT BOOLEAN,
                                  po_OutRec OUT apps.mtl_system_items_b_kfv%ROWTYPE,
                                  po_WarningDisableWholeType OUT BOOLEAN,
                                  po_WarningDisableThisPart OUT BOOLEAN)
    RETURN varchar2
    IS
      vn_TmpQtyCats number;
    BEGIN -- GetAndVerifyInvPart
      
      po_OutIsSet := FALSE;
      
      SELECT * INTO po_OutRec
      FROM apps.mtl_system_items_b_kfv
      WHERE segment1 = pi_GivenPartName AND organization_id = 0
      AND inventory_item_status_code = 'Active';
      
      po_OutIsSet := TRUE;
      
      SELECT COUNT(*) INTO vn_TmpQtyCats FROM apps.mtl_item_categories
      WHERE inventory_item_id = po_OutRec.inventory_item_id AND organization_id = 0
      AND category_set_id IN (nCSetR,nCSetN,nCSetB,nCSetG);
      
      -- COUNT should be 1, otherwise it is a problem
      
      IF vn_TmpQtyCats = 0 AND pi_GivenPartType ='504'
      THEN
        po_WarningDisableWholeType := FALSE;
        po_WarningDisableThisPart := FALSE;
        RETURN 'Internal Error 2046 - Part '||po_OutRec.segment1||
                ' does not have correct category setup in Oracle.'||
                ' Somehow, the CutSchedule failed to find this error.'||
                ' Please contact MIS.';
      ELSIF vn_TmpQtyCats = 0 AND pi_GivenPartType != '504'
      THEN
        -- Possibly internal error,
        -- I'm not sure how we got this far into the system
        -- (after reco_rstx_originvqty has been mostly setup)
        -- and, somehow, one of the parts don't have any relevant categories
        po_WarningDisableWholeType := TRUE;
        po_WarningDisableThisPart := FALSE;
        RETURN 'DONE';
      ELSIF vn_TmpQtyCats > 1 AND pi_GivenPartType = '504'
      THEN
        po_WarningDisableWholeType := FALSE;
        po_WarningDisableThisPart := FALSE;
        RETURN 'Error: Part '||po_OutRec.segment1||' does not have correct '||
                'category setup in Oracle. Please contact Purchasing.';
      ELSIF vn_TmpQtyCats > 1 AND pi_GivenPartType != '504'
      THEN
        po_WarningDisableWholeType := TRUE;
        po_WarningDisableThisPart := FALSE;
        RETURN 'DONE';
      END IF;
      
      po_WarningDisableWholeType := FALSE;
      po_WarningDisableThisPart := FALSE;
      RETURN 'DONE';
    EXCEPTION -- GetAndVerifyInvPart
      WHEN NO_DATA_FOUND
      THEN
        IF pi_GivenPartCatSet = nCSetR
        THEN
          po_OutIsSet := FALSE;
          po_OutRec := NULL;
          po_WarningDisableWholeType := FALSE;
          po_WarningDisableThisPart := FALSE;
          RETURN 'DONE';
        ELSIF pi_GivenPartCatSet != nCSetR
        AND pi_GivenPartLength >= pi_min_cut_allowed
        AND pi_GivenPartLength <= pi_max_cut_allowed
        THEN
          IF pi_GivenPartType = '504'
          THEN
            po_OutIsSet := FALSE;
            po_OutRec := NULL;
            po_WarningDisableWholeType := FALSE;
            po_WarningDisableThisPart := FALSE;
            RETURN 'Error: Part '||pi_GivenPartName||
                    ' is not setup in Oracle. Please contact Purchasing.';
          ELSIF pi_GivenPartType != '504'
          THEN
            po_OutIsSet := FALSE;
            po_OutRec := NULL;
            po_WarningDisableWholeType := TRUE;
            po_WarningDisableThisPart := FALSE;
            RETURN 'DONE';
          END IF;
        ELSIF pi_GivenPartCatSet != nCSetR
        AND ( pi_GivenPartLength < pi_min_cut_allowed
              OR pi_GivenPartLength > pi_max_cut_allowed )
        THEN
          po_OutIsSet := FALSE;
          po_OutRec := NULL;
          po_WarningDisableWholeType := FALSE;
          po_WarningDisableThisPart := TRUE;
          RETURN 'DONE';
        END IF;
      WHEN TOO_MANY_ROWS
      THEN
        po_OutIsSet := FALSE;
        po_OutRec := NULL;
        po_WarningDisableWholeType := FALSE;
        po_WarningDisableThisPart := FALSE;
        RETURN 'Internal Error 2041 - Duplicate Part Defined for '||
                pi_GivenPartName||'. Please contact Purchsing.';
      WHEN others
      THEN
        po_OutIsSet := FALSE;
        po_OutRec := NULL;
        po_WarningDisableWholeType := FALSE;
        po_WarningDisableThisPart := FALSE;
        RETURN 'Internal Error 2042 - Unknown Error: Contact MIS';
    END; -- GetAndVerifyInvPart
    
    FUNCTION UpdateExistingROIQRec (pi_GivenPartName IN varchar2,
                                    pi_GivenPartInvItemId IN number)
    RETURN varchar2
    IS
    BEGIN -- UpdateExistingROIQRec
      
      UPDATE reco_rstx_originvqty
      set inventory_item_id = pi_GivenPartInvItemId
      WHERE segment1 = pi_GivenPartName;
      
      IF SQL%ROWCOUNT != 1
      THEN RETURN 'Internal Error 2043 - '||pi_GivenPartName||' - Contact MIS';
      END IF;
      
      RETURN 'DONE';
    END; -- UpdateExistingROIQRec
    
  BEGIN
    FOR nPartTypeCtr IN 1 .. oDemandedPartTypes.count
    LOOP
      DECLARE -- items for each length in the current parttype
        vc_TmpCharLen varchar2(2);
        
        vb_NUBInvRecSet BOOLEAN;
        vr_NUBInvRec apps.mtl_system_items_b_kfv%ROWTYPE;
        vb_SMBInvRecSet BOOLEAN;
        vr_SMBInvRec apps.mtl_system_items_b_kfv%ROWTYPE;
        vb_NPBInvRecSet BOOLEAN;
        vr_NPBInvRec apps.mtl_system_items_b_kfv%ROWTYPE;
        vb_SPBInvRecSet BOOLEAN;
        vr_SPBInvRec apps.mtl_system_items_b_kfv%ROWTYPE;
        vb_DPBInvRecSet BOOLEAN;
        vr_DPBInvRec apps.mtl_system_items_b_kfv%ROWTYPE;
        vb_SPGInvRecSet BOOLEAN;
        vr_SPGInvRec apps.mtl_system_items_b_kfv%ROWTYPE;
        vb_DPGInvRecSet BOOLEAN;
        vr_DPGInvRec apps.mtl_system_items_b_kfv%ROWTYPE;
        
        vb_DisableWholeType BOOLEAN;
        vb_DisableThisPart BOOLEAN;
        
        vc_TempOutput varchar2(1000);
      BEGIN
        
        FOR nCtrLength IN 1 .. 47
        LOOP
          vc_TmpCharLen := TO_CHAR(nCtrLength);
          IF nCtrLength < 10
          THEN vc_TmpCharLen := '0'||TO_CHAR(nCtrLength);
          END IF;
          
          vb_NUBInvRecSet := FALSE;
          vr_NUBInvRec := NULL; -- "if vr_... is null" test does not compile
          vb_SMBInvRecSet := FALSE;
          vr_SMBInvRec := NULL;
          vb_NPBInvRecSet := FALSE;
          vr_NPBInvRec := NULL;
          vb_SPBInvRecSet := FALSE;
          vr_SPBInvRec := NULL;
          vb_DPBInvRecSet := FALSE;
          vr_DPBInvRec := NULL;
          vb_SPGInvRecSet := FALSE;
          vr_SPGInvRec := NULL;
          vb_DPGInvRecSet := FALSE;
          vr_DPGInvRec := NULL;
          
          ---
          -- Start GET INVENTORY RECORDS FOR THIS PARTTYPE/LENGTH
          
            vc_TempOutput := GetAndVerifyInvPart(
              'NU'||oDemandedPartTypes(nPartTypeCtr)||'B'||vc_TmpCharLen,
              nCSetR,nCtrLength,oDemandedPartTypes(nPartTypeCtr),
              vb_NUBInvRecSet,vr_NUBInvRec,
              vb_DisableWholeType,vb_DisableThisPart);
            
            /*if vc_TempOutput != 'DONE' then continue; end if; -- return vc_TempOutput; end if;
            
            if vb_DisableWholeType = true or vb_DisableThisPart = true
            then continue; end if;
            */
            vc_TempOutput := GetAndVerifyInvPart(
              'SM'||oDemandedPartTypes(nPartTypeCtr)||'B'||vc_TmpCharLen,
              nCSetR,nCtrLength,oDemandedPartTypes(nPartTypeCtr),
              vb_SMBInvRecSet,vr_SMBInvRec,
              vb_DisableWholeType,vb_DisableThisPart);
            
            /*if vc_TempOutput != 'DONE' then continue; end if; -- return vc_TempOutput; end if;
            
            if vb_DisableWholeType = true or vb_DisableThisPart = true
            then continue; end if;
            */
            vc_TempOutput := GetAndVerifyInvPart(
              'N'||oDemandedPartTypes(nPartTypeCtr)||'B'||vc_TmpCharLen,
              nCSetN,nCtrLength,oDemandedPartTypes(nPartTypeCtr),
              vb_NPBInvRecSet,vr_NPBInvRec,
              vb_DisableWholeType,vb_DisableThisPart);
            
            /*if vc_TempOutput != 'DONE' then continue; end if; -- return vc_TempOutput; end if;
                        

            if vb_DisableWholeType = true or vb_DisableThisPart = true
            then continue; end if;
            */
            vc_TempOutput := GetAndVerifyInvPart(
              'S'||oDemandedPartTypes(nPartTypeCtr)||'B'||vc_TmpCharLen,
              nCSetB,nCtrLength,oDemandedPartTypes(nPartTypeCtr),
              vb_SPBInvRecSet,vr_SPBInvRec,
              vb_DisableWholeType,vb_DisableThisPart);
            
            /*if vc_TempOutput != 'DONE' then continue; end if; -- return vc_TempOutput; end if;
            
            if vb_DisableWholeType = true or vb_DisableThisPart = true
            then continue; end if;
            */
            vc_TempOutput := GetAndVerifyInvPart(
              'D'||oDemandedPartTypes(nPartTypeCtr)||'B'||vc_TmpCharLen,
              nCSetB,nCtrLength,oDemandedPartTypes(nPartTypeCtr),
              vb_DPBInvRecSet,vr_DPBInvRec,
              vb_DisableWholeType,vb_DisableThisPart);
            
            /*if vc_TempOutput != 'DONE' then continue; end if; -- return vc_TempOutput; end if;
            
            if vb_DisableWholeType = true or vb_DisableThisPart = true
            then continue; end if;
            */
            vc_TempOutput := GetAndVerifyInvPart(
              'S'||oDemandedPartTypes(nPartTypeCtr)||'G'||vc_TmpCharLen,
              nCSetG,nCtrLength,oDemandedPartTypes(nPartTypeCtr),
              vb_SPGInvRecSet,vr_SPGInvRec,
              vb_DisableWholeType,vb_DisableThisPart);
            
            /*if vc_TempOutput != 'DONE' then continue; end if; -- return vc_TempOutput; end if;
            
            if vb_DisableWholeType = true or vb_DisableThisPart = true
            then continue; end if;
            */
            vc_TempOutput := GetAndVerifyInvPart(
              'D'||oDemandedPartTypes(nPartTypeCtr)||'G'||vc_TmpCharLen,
              nCSetG,nCtrLength,oDemandedPartTypes(nPartTypeCtr),
              vb_DPGInvRecSet,vr_DPGInvRec,
              vb_DisableWholeType,vb_DisableThisPart);
            
            /*if vc_TempOutput != 'DONE' then continue; end if; -- return vc_TempOutput; end if;
            
            if vb_DisableWholeType = true or vb_DisableThisPart = true
            then continue; end if;
            */
          
          ---
          -- End GET INVENTORY RECORDS FOR THIS PARTTYPE/LENGTH
          
          ---
          -- Start HANDLE WARNINGS FOR THIS PARTTYPE/LENGTH
          
/*          if vb_DisableWholeType = true
          then
            -- Disable any old parts that were already modified
            -- (earlier loop iterations)
            update reco_rstx_originvqty
            set inventory_item_id = null                            -- JNL COMMENTING NULL
            where thetype = oDemandedPartTypes(nPartTypeCtr);
            
            -- Skip this length, and all future lengths, for this parttype
            continue; -- Goto next parttype in parent loop
          end if;
          
          if vb_DisableThisPart = true
          then
            -- This line is extra precaution / future-proofing
            --update reco_rstx_originvqty
            --set inventory_item_id = null                          -- JNL COMMENTING NULL
            --where thetype = oDemandedPartTypes(nPartTypeCtr)
            --and numlength = nCtrLength;
            
            -- Skip this length/parttype and move to next length
            continue; -- Goto next length in current loop
          end if;
*/
          ---
          -- End HANDLE WARNINGS FOR THIS PARTTYPE/LENGTH
          
          ---
          -- Start UPDATE THE RECO_RSTX_ORIGINVQTY RECS BECAUSE SUCCESSFUL
          
          IF vb_NUBInvRecSet = TRUE
          THEN
            vc_TempOutput := UpdateExistingROIQRec(
              vr_NUBInvRec.segment1,vr_NUBInvRec.inventory_item_id);
            
            --if vc_TempOutput != 'DONE' then continue; end if; -- return vc_TempOutput; end if;

          END IF;
          
          IF vb_SMBInvRecSet = TRUE
          THEN
            vc_TempOutput := UpdateExistingROIQRec(
              vr_SMBInvRec.segment1,vr_SMBInvRec.inventory_item_id);
            
            --if vc_TempOutput != 'DONE' then continue; end if; -- return vc_TempOutput; end if;

          END IF;
          
          IF vb_NPBInvRecSet = TRUE
          THEN
            vc_TempOutput := UpdateExistingROIQRec(
              vr_NPBInvRec.segment1,vr_NPBInvRec.inventory_item_id);
            
            --if vc_TempOutput != 'DONE' then continue; end if; -- return vc_TempOutput; end if;

          END IF;
          
          IF vb_SPBInvRecSet = TRUE
          THEN
            vc_TempOutput := UpdateExistingROIQRec(
              vr_SPBInvRec.segment1,vr_SPBInvRec.inventory_item_id);
            
           -- if vc_TempOutput != 'DONE' then continue; end if; -- return vc_TempOutput; end if;

          END IF;
          
          IF vb_DPBInvRecSet = TRUE
          THEN
            vc_TempOutput := UpdateExistingROIQRec(
              vr_DPBInvRec.segment1,vr_DPBInvRec.inventory_item_id);
            
           -- if vc_TempOutput != 'DONE' then continue; end if; -- return vc_TempOutput; end if;

          END IF;
          
          IF vb_SPGInvRecSet = TRUE
          THEN
            vc_TempOutput := UpdateExistingROIQRec(
              vr_SPGInvRec.segment1,vr_SPGInvRec.inventory_item_id);
            
           -- if vc_TempOutput != 'DONE' then continue; end if; -- return vc_TempOutput; end if;

          END IF;
          
          IF vb_DPGInvRecSet = TRUE
          THEN
            vc_TempOutput := UpdateExistingROIQRec(
              vr_DPGInvRec.segment1,vr_DPGInvRec.inventory_item_id);
            
            --if vc_TempOutput != 'DONE' then continue; end if; -- return vc_TempOutput; end if;

          END IF;
          
          ---
          -- End UPDATE THE RECO_RSTX_ORIGINVQTY RECS BECAUSE SUCCESSFUL
          
        END LOOP; -- Loop for lengths
        
        IF vb_DisableWholeType = TRUE
        THEN CONTINUE; -- Goto next parttype in parent loop
        END IF;
        
        vb_NUBInvRecSet := FALSE; -- NU...B48
        vr_NUBInvRec := NULL; -- "if vr_... is null" test does not compile
        vb_NPBInvRecSet := FALSE; -- NU...B49 -- Bad variable re-use
        vr_NPBInvRec := NULL;
        vb_SMBInvRecSet := FALSE; -- SM...B48
        vr_SMBInvRec := NULL;
        vb_SPBInvRecSet := FALSE; -- SM...B49 -- Bad variable re-use
        vr_SPBInvRec := NULL;
        

          vc_TempOutput := GetAndVerifyInvPart(
            'NU'||oDemandedPartTypes(nPartTypeCtr)||'B48',
            nCSetR,48,oDemandedPartTypes(nPartTypeCtr),
            vb_NUBInvRecSet,vr_NUBInvRec,
            vb_DisableWholeType,vb_DisableThisPart);
          
            --if vc_TempOutput != 'DONE' then continue; end if; -- return vc_TempOutput; end if;

          
          --if vb_DisableWholeType = true or vb_DisableThisPart = true
          --then continue; end if;
          
          vc_TempOutput := GetAndVerifyInvPart(
            'NU'||oDemandedPartTypes(nPartTypeCtr)||'B49',
            nCSetR,48,oDemandedPartTypes(nPartTypeCtr),
            vb_NPBInvRecSet,vr_NPBInvRec,
            vb_DisableWholeType,vb_DisableThisPart);
          
          --  if vc_TempOutput != 'DONE' then continue; end if; -- return vc_TempOutput; end if;

          
          --if vb_DisableWholeType = true or vb_DisableThisPart = true
          --then continue; end if;
          
          vc_TempOutput := GetAndVerifyInvPart(
            'SM'||oDemandedPartTypes(nPartTypeCtr)||'B48',
            nCSetR,48,oDemandedPartTypes(nPartTypeCtr),
            vb_SMBInvRecSet,vr_SMBInvRec,
            vb_DisableWholeType,vb_DisableThisPart);
          
          --  if vc_TempOutput != 'DONE' then continue; end if; -- return vc_TempOutput; end if;

          
          --if vb_DisableWholeType = true or vb_DisableThisPart = true
          --then continue; end if;
          
          vc_TempOutput := GetAndVerifyInvPart(
            'SM'||oDemandedPartTypes(nPartTypeCtr)||'B49',
            nCSetR,48,oDemandedPartTypes(nPartTypeCtr),
            vb_SPBInvRecSet,vr_SPBInvRec,
            vb_DisableWholeType,vb_DisableThisPart);
          
            --if vc_TempOutput != 'DONE' then continue; end if; -- return vc_TempOutput; end if;

          
          --if vb_DisableWholeType = true or vb_DisableThisPart = true
          --then continue; end if;
          
        
/*        if vb_DisableWholeType = true
        then
          -- Disable any old parts that were already modified
          -- (earlier loop iterations)
          update reco_rstx_originvqty
          set inventory_item_id = null                                -- JNL COMMENTING NULL
          where thetype = oDemandedPartTypes(nPartTypeCtr);
          
          -- Skip this length, and all future lengths, for this parttype
          continue; -- Goto next parttype in loop
        end if;
*/        
        IF vb_DisableThisPart = TRUE
        THEN
          -- This line is extra precaution / future-proofing
          UPDATE reco_rstx_originvqty
          set inventory_item_id = NULL                                -- JNL COMMENTING NULL
          WHERE thetype = oDemandedPartTypes(nPartTypeCtr)
          AND (numlength = 48 OR numlength = 49);
          
          -- Skip this length/parttype and move to next length
          CONTINUE; -- Goto next parttype in loop
        END IF;
        
        IF vb_NUBInvRecSet = TRUE
        THEN
          vc_TempOutput := UpdateExistingROIQRec(
            vr_NUBInvRec.segment1,vr_NUBInvRec.inventory_item_id);
          
            --if vc_TempOutput != 'DONE' then continue; end if; -- return vc_TempOutput; end if;

        END IF;
        
        IF vb_NPBInvRecSet = TRUE
        THEN
          vc_TempOutput := UpdateExistingROIQRec(
            vr_NPBInvRec.segment1,vr_NPBInvRec.inventory_item_id);
          
            --if vc_TempOutput != 'DONE' then continue; end if; -- return vc_TempOutput; end if;

        END IF;
        
        IF vb_SMBInvRecSet = TRUE
        THEN
          vc_TempOutput := UpdateExistingROIQRec(
            vr_SMBInvRec.segment1,vr_SMBInvRec.inventory_item_id);
          
           -- if vc_TempOutput != 'DONE' then continue; end if; -- return vc_TempOutput; end if;

        END IF;
        
        IF vb_SPBInvRecSet = TRUE
        THEN
          vc_TempOutput := UpdateExistingROIQRec(
            vr_SPBInvRec.segment1,vr_SPBInvRec.inventory_item_id);
          
            --if vc_TempOutput != 'DONE' then continue; end if; -- return vc_TempOutput; end if;

        END IF;
        
      END; -- Inner declare for each length of the current parttype
    END LOOP; -- Loop for each parttype
  END; -- Big declare for all updating inventory parts
  
  ----------
  -- If we get here, then we know that:
  -- - All demanded parttypes/lengths are in reco_rstx_originvqty table
  -- - Those records in reco_rstx_originvqty may have null inventory_item_id
  --   (which indicates an error with that part in inventory)
  -- - Due to the above logic, we know the following information about
  --   whether inventory_item_id is null
  --   1) Case: All the parttype has inventory_item_id of null
  --            e.g. NU506B10 null, SM506B10 null, N506B10 null,
  --                 S506B10 null, D506B10 null, S506G10 null, D506G10 null
  --                 ...
  --                 NU506B11 null, SM506B11 null, N506B11 null,
  --                 S506B11 null, D506B11 null, S506G11 null, D506G11 null
  --                 ...
  --                 12, 13 etc ...
  --   2) Case: Some parts within the parttype are null
  --            e.g. For only 504 parts, then these parts have null InvItemId
  --                 NU504B03 null, SM504B03 null, N504B03 null,
  --                 S504B03 null, D504B03 null, S504G03 null, D504G03 null
  --                 but all the other parts for 504 are okay
  --   3) Case: Some parts have only the RawStl version with null InvItemId
  --            e.g. NU504B10 null, SM504B10 null,
  --                 but the other N504B10 and S504B10 etc ... are okay
  --   4) Case: All the parts for a parttype have inventory_item_id set
  --            e.g. Inventory is setup correctly !!
  
  ----------
  -- Check - Galvanized Parts have their precursor set correctly
  --         (Handle for non-important part-lengths e.g. 04 length strips)
  
  DECLARE
    TYPE rec_InvalidPart IS record
              (numlength number,thetype apps.mtl_system_items_b_kfv.segment1%TYPE);
    
    TYPE coll_InvalidPart IS TABLE OF rec_InvalidPart;
    
    oTheInvalidParts coll_InvalidPart; -- Fetched, so don't initialize
  BEGIN
    SELECT DISTINCT roiq.numlength, roiq.thetype
    BULK COLLECT INTO oTheInvalidParts
    FROM  reco_rstx_originvqty roiq
    WHERE roiq.inventory_item_id IS NOT NULL
    AND roiq.category_set_id = nCSetG
    AND (numlength < pi_min_cut_allowed OR numlength > pi_max_cut_allowed)
    AND (
          roiq.actual_attribute4 IS NULL
          OR
          NOT EXISTS (SELECT 'Y'
                      FROM reco_rstx_originvqty subQ
                      WHERE subQ.inventory_item_id IS NOT NULL
                      AND subQ.segment1 = roiq.actual_attribute4)
        );
    
--    for ctr in 1 .. oTheInvalidParts.count
--    loop
--      update reco_rstx_originvqty
--      set inventory_item_id = null                                -- JNL COMMENTING NULL
--      where thetype = oTheInvalidParts(ctr).thetype
--      and numlength = oTheInvalidParts(ctr).numlength;
--    end loop;
  END;
  
  ----------
  -- Check - Galvanized Parts have their precursor set correctly
  --         (Handle for core part-lengths e.g. 12 footers)
  
  DECLARE
    TYPE rec_InvalidType IS record
              (thetype apps.mtl_system_items_b_kfv.segment1%TYPE);
    
    TYPE coll_InvalidType IS TABLE OF rec_InvalidType;
    
    oTheInvalidTypes coll_InvalidType; -- Fetched, so don't initialize
  BEGIN
    SELECT DISTINCT roiq.thetype
    BULK COLLECT INTO oTheInvalidTypes
    FROM  reco_rstx_originvqty roiq
    WHERE roiq.inventory_item_id IS NOT NULL
    AND roiq.category_set_id = nCSetG
    AND numlength >= pi_min_cut_allowed
    AND numlength <= pi_max_cut_allowed
    AND (
          roiq.actual_attribute4 IS NULL
          OR
          NOT EXISTS (SELECT 'Y'
                      FROM reco_rstx_originvqty subQ
                      WHERE subQ.inventory_item_id IS NOT NULL
                      AND subQ.segment1 = roiq.actual_attribute4)
        );
    
--    for ctr in 1 .. oTheInvalidTypes.count
--    loop
--      update reco_rstx_originvqty
--      set inventory_item_id = null                          -- JNL COMMENTING NULL
--      where thetype = oTheInvalidTypes(ctr).thetype;
--    end loop;
  END;
  
  ----------
  -- Check - Cut matrix should exist for each core length
  
  DECLARE
    CURSOR cur_MtxLens (pi_GivenPartType IN varchar2)
    IS
      SELECT DISTINCT cutpce.unit_volume
      FROM reco_rstx_cutmtx cutmtx, reco_rstx_cutpce cutpce
      WHERE cutmtx.cutmtx_id = cutpce.cutmtx_id
      AND cutmtx.ptype = pi_GivenPartType
      AND cutpce.piece_number = 1
      ORDER BY cutpce.unit_volume;
    
    vn_LengthCtr number;
  BEGIN
    FOR typectr IN 1 .. oDemandedPartTypes.count
    LOOP
      vn_LengthCtr := pi_min_cut_allowed;
      FOR rec_MtxLens IN cur_MtxLens (oDemandedPartTypes(typectr))
      LOOP
        IF vn_LengthCtr = rec_MtxLens.unit_volume
        THEN vn_LengthCtr := vn_LengthCtr + 1;
        END IF;
      END LOOP;
      IF vn_LengthCtr <= pi_max_cut_allowed
      THEN RETURN 'Internal Error 2025 - Cut Mtx not setup for part '||
                  oDemandedPartTypes(typectr)||'. Contact MIS.';
      END IF;
    END LOOP;
  END;
  
  RETURN 'DONE';
  
END; -- validate_and_count_inv

--------------------------------------------------------------------------------
-- setup_cut_requirements
-- 
-- Looks at SHIPPING for RSTX, figures out which cuts are needed by which days,
-- and adds the information to reco_rstx_cutreqv2 table
-- 
-- It is possible to have an entry in reco_rstx_cutreqv2 that does not
-- have any required qty (e.g. qty_req_black is 0, qty_req_galv is 0 ...)
-- This happens whenever we satisfy a requirement without budgeting
-- a "New cutting need":
-- : when we convert existing inventory (B -> G) to fill a galv requirement,
-- : when we convert existing raw-steel (not 48' / 49') to fill a requirement
-- This way, the cutreq table tracks any assumptions / conversions from
-- outside of the system.
-- 
-- We ignore any requirements where the part has inventory_item_id null
-- in the reco_rstx_originvqty table.
-- If the part has null inventory_item_id, then we ignore it
-- (the shipment's demand does not go into reco_rstx_cutreq calcs)
-- 
-- PRE-CONDITIONS
-- : clear_existing_reqsandplans
-- : validate_and_count_inv should have completed successfully
--   (it should have returned 'DONE' message)
-- : pi_first_date_of_reqs is the first date we start looking for shipments that
--   haven't been sent yet. It can be before sysdate if desired (to grab
--   shipments from yesterday etc...)
-- : pi_min_cut_allowed should reflect the minimum piece length we want
--   to consider. If a shipment has lengths less-than the minimum size, the
--   system will generate exception for that piece
-- : pi_max_cut_allowed should reflect the maximum piece length we want
--   to consider. If a shipment has lengths more-than the maximum size, the
--   system will generate exception for that piece
PROCEDURE setup_cut_requirements (pi_first_date_of_reqs IN date,
                                  pi_min_cut_allowed IN number,
                                  pi_max_cut_allowed IN number,
                                  pi_ignore_curr_np_inv IN varchar2)
IS
  -- Intentional: Lumps black/galv version of things together
  CURSOR cur_ShipmentDemand
  IS
    SELECT  /*+ RULE */DISTINCT TRUNC(rs.truck_date) thedate,
            roiq.numlength thelength,
            roiq.thetype thetype,
            roiq.thepunch thepunch,
            roiq.charlength charlength,
            CASE
            WHEN roiq.thepunch = 'N'
            THEN 1
            WHEN roiq.thepunch = 'D'
            THEN 2
            WHEN roiq.thepunch = 'S'
            THEN 3
            ELSE 4
            END sortord_punch
    FROM    reco_truck rs,
            reco_truckstop_parts_v rsp,
            reco_rstx_originvqty roiq
    WHERE   rs.truck_id = rsp.stop_truck_id
    AND     rsp.part_id = roiq.inventory_item_id
    AND     rs.truck_status IN ('A','H','B')
    AND     rsp.orig_subinventory_code IN ('RSTX')
    AND     NVL(rsp.quantity,0) > 0
    AND     rs.truck_date >= pi_first_date_of_reqs
    AND     roiq.numlength >= pi_min_cut_allowed
    AND     roiq.numlength <= pi_max_cut_allowed
    AND     roiq.inventory_item_id IS NOT NULL
    ORDER BY  roiq.numlength desc,  -- Always analyze longer before shorter
              roiq.thetype,         -- And always break-out length/type
              TRUNC(rs.truck_date), -- before the date consideration
              CASE
              WHEN roiq.thepunch = 'N'
              THEN 1
              WHEN roiq.thepunch = 'D'
              THEN 2
              WHEN roiq.thepunch = 'S'
              THEN 3
              ELSE 4
              END; -- sort order changed May-2013 DSM
  
  TYPE coll_ShipmentDemand IS TABLE OF cur_ShipmentDemand%ROWTYPE;
  oTheShipmentDemand coll_ShipmentDemand; -- Fetched, so don't initialize
  
  rec_CurrCalc reco_rstx_cutreqcalc%ROWTYPE;
  
  vn_CurrentQtyRawStl number;
  vn_CurrentQtyNPB number;
  vn_CurrentQtyNPG number;
  vn_CurrentQtySPB number;
  vn_CurrentQtySPG number;
  vn_CurrentQtyDPB number;
  vn_CurrentQtyDPG number;
  
  vn_CurrBlackQtyThisRec number;
  vn_CurrGalvQtyThisRec number;
  
BEGIN -- setup_cut_requirements
  
  ---
  -- Gather all sorts of knowledge about the date/type/punch demand
  -- from shipping, and use the reco_rstx_cutreqcalc table to store calcs
  ---
  
  DELETE FROM reco_rstx_cutreqcalc;
  
  OPEN cur_ShipmentDemand;
  FETCH cur_ShipmentDemand BULK COLLECT INTO oTheShipmentDemand;
  CLOSE cur_ShipmentDemand;
  
  FOR collCtr IN 1 .. oTheShipmentDemand.count -- Oracle collections start at 1 ...
  LOOP
    
    ----------
    -- Basic data for reqcalc
    ----------
    
    rec_CurrCalc.thedate :=
      oTheShipmentDemand(collCtr).thedate;
    
    rec_CurrCalc.thelength :=
      oTheShipmentDemand(collCtr).thelength;
    
    rec_CurrCalc.thetype :=
      oTheShipmentDemand(collCtr).thetype;
    
    rec_CurrCalc.thepunch :=
      oTheShipmentDemand(collCtr).thepunch;
    
    ----------
    -- We track inventory per parttype/partlength, so initialize
    -- (and we track all 3 punches inventory together)
    ----------
    
    -- Reset if we are looking at a new partlength / parttype
    IF collCtr = 1
    OR oTheShipmentDemand(collCtr).thelength
          != oTheShipmentDemand(collCtr-1).thelength
    OR oTheShipmentDemand(collCtr).thetype
          != oTheShipmentDemand(collCtr-1).thetype
    THEN
      vn_CurrentQtyRawStl := 0;
      vn_CurrentQtyNPB := 0;
      vn_CurrentQtyNPG := 0;
      vn_CurrentQtySPB := 0;
      vn_CurrentQtySPG := 0;
      vn_CurrentQtyDPB := 0;
      vn_CurrentQtyDPG := 0;
      
      DECLARE
        vn_TotNU number;
        vn_TotSM number;
      BEGIN
        SELECT quantity INTO vn_TotNU
        FROM reco_rstx_originvqty
        WHERE category_set_id = nCSetR
        AND thepunch = 'NU'
        AND thetype = oTheShipmentDemand(collCtr).thetype
        AND thecoat = 'B'
        AND charlength = oTheShipmentDemand(collCtr).charlength;
        
        IF vn_TotNU < 0 -- Added FEB2013
        THEN vn_TotNU := 0; END IF;
        
        SELECT quantity INTO vn_TotSM
        FROM reco_rstx_originvqty
        WHERE category_set_id = nCSetR
        AND thepunch = 'SM'
        AND thetype = oTheShipmentDemand(collCtr).thetype
        AND thecoat = 'B'
        AND charlength = oTheShipmentDemand(collCtr).charlength;
        
        IF vn_TotSM < 0 -- Added FEB2013
        THEN vn_TotSM := 0; END IF;
        
        vn_CurrentQtyRawStl := vn_TotNU + vn_TotSM;
      END;
      
      -- DSM - JUL 2013 - RECO is moving to process of:
      --                  Shear -> DirectTo -> Punch
      --                  so the NoPunch inventory sitting on the side is
      --                  reserved for "slow days" or "special processing".
      --                  We can pretend like the NP Inventory doesn't
      --                  exist when doing the scheduling
      IF pi_ignore_curr_np_inv = 'N'
      THEN
        SELECT  oiq.quantity
        INTO  vn_CurrentQtyNPB
        FROM  reco_rstx_originvqty oiq
        WHERE   oiq.thepunch = 'N'
        AND     oiq.thetype = oTheShipmentDemand(collCtr).thetype
        AND     oiq.thecoat = 'B'
        AND     oiq.charlength = oTheShipmentDemand(collCtr).charlength;
        
        IF vn_CurrentQtyNPB < 0 -- Added FEB2013
        THEN vn_CurrentQtyNPB := 0; END IF;
        
        vn_CurrentQtyNPG := 0;
        --  select  oiq.quantity
        --  into  vn_CurrQtyNPG
        --  from  reco_rstx_originvqty oiq
        --  where   oiq.thepunch = 'N'
        --  and     oiq.thetype = oTheShipmentDemand(collCtr).thetype
        --  and     oiq.thecoat = 'G'
        --  and     oiq.charlength = oTheShipmentDemand(collCtr).charlength;
        --  
        --  if vn_CurrentQtyNPG < 0 -- Added FEB2013
        --  then vn_CurrentQtyNPG := 0; end if;
      END IF; -- pi_ignore_curr_np_inv = 'N'
      
      SELECT  oiq.quantity
      INTO  vn_CurrentQtySPB
      FROM  reco_rstx_originvqty oiq
      WHERE   oiq.thepunch = 'S'
      AND     oiq.thetype = oTheShipmentDemand(collCtr).thetype
      AND     oiq.thecoat = 'B'
      AND     oiq.charlength = oTheShipmentDemand(collCtr).charlength;
      
      IF vn_CurrentQtySPB < 0 -- Added FEB2013
      THEN vn_CurrentQtySPB := 0; END IF;
      
      SELECT  oiq.quantity
      INTO  vn_CurrentQtySPG
      FROM  reco_rstx_originvqty oiq
      WHERE   oiq.thepunch = 'S'
      AND     oiq.thetype = oTheShipmentDemand(collCtr).thetype
      AND     oiq.thecoat = 'G'
      AND     oiq.charlength = oTheShipmentDemand(collCtr).charlength;
      
      IF vn_CurrentQtySPG < 0 -- Added FEB2013
      THEN vn_CurrentQtySPG := 0; END IF;
      
      SELECT  oiq.quantity
      INTO  vn_CurrentQtyDPB
      FROM  reco_rstx_originvqty oiq
      WHERE   oiq.thepunch = 'D'
      AND     oiq.thetype = oTheShipmentDemand(collCtr).thetype
      AND     oiq.thecoat = 'B'
      AND     oiq.charlength = oTheShipmentDemand(collCtr).charlength;
      
      IF vn_CurrentQtyDPB < 0 -- Added FEB2013
      THEN vn_CurrentQtyDPB := 0; END IF;
      
      SELECT  oiq.quantity
      INTO  vn_CurrentQtyDPG
      FROM  reco_rstx_originvqty oiq
      WHERE   oiq.thepunch = 'D'
      AND     oiq.thetype = oTheShipmentDemand(collCtr).thetype
      AND     oiq.thecoat = 'G'
      AND     oiq.charlength = oTheShipmentDemand(collCtr).charlength;
      
      IF vn_CurrentQtyDPG < 0 -- Added FEB2013
      THEN vn_CurrentQtyDPG := 0; END IF;
      
    END IF; -- Reset if we are looking at a new partlength / parttype
    
    ----------
    -- Because we are breaking out the N/S/D tracking in some ways,
    -- then it is easiest to include a SINGLE IF STATEMENT here
    -- instead of repeating the same IF N IF S IF D ...
    ----------
    
    vn_CurrBlackQtyThisRec := 0;
    vn_CurrGalvQtyThisRec := 0;
    
    IF oTheShipmentDemand(collCtr).thepunch = 'N'
    THEN
      vn_CurrBlackQtyThisRec := vn_CurrentQtyNPB;
      vn_CurrGalvQtyThisRec := vn_CurrentQtyNPG;
    ELSIF oTheShipmentDemand(collCtr).thepunch = 'S'
    THEN
      vn_CurrBlackQtyThisRec := vn_CurrentQtySPB;
      vn_CurrGalvQtyThisRec := vn_CurrentQtySPG;
    ELSIF oTheShipmentDemand(collCtr).thepunch = 'D'
    THEN
      vn_CurrBlackQtyThisRec := vn_CurrentQtyDPB;
      vn_CurrGalvQtyThisRec := vn_CurrentQtyDPG;
    END IF;
    
    ----------
    -- Set start of day inventory for this parttype/partlength
    ----------
    
    rec_CurrCalc.rawsteel_start_inv := vn_CurrentQtyRawStl;
    
    rec_CurrCalc.black_daystart_inv := vn_CurrBlackQtyThisRec;
    
    rec_CurrCalc.galv_daystart_inv := vn_CurrGalvQtyThisRec;
    
    ----------
    -- Set day demand for this date for this parttype/partlength
    ----------
    
    SELECT  SUM(rsp.quantity)
    INTO  rec_CurrCalc.black_daydemand
    FROM  reco_truckstop_parts rsp,
          reco_truck rs,
          reco_rstx_originvqty roiq
    WHERE rs.truck_id = rsp.stop_truck_id
    AND rsp.orig_subinventory_code IN ('RSTX')
    AND rs.truck_status IN ('A','H','B')
    AND rs.truck_date
            >= TRUNC(oTheShipmentDemand(collCtr).thedate)
    AND rs.truck_date
            < TRUNC(oTheShipmentDemand(collCtr).thedate) + 1
    AND rsp.part_id = roiq.inventory_item_id
    AND roiq.segment1 LIKE
                      oTheShipmentDemand(collCtr).thepunch||
                      oTheShipmentDemand(collCtr).thetype||
                      'B'||
                      oTheShipmentDemand(collCtr).charlength;
    
    rec_CurrCalc.black_daydemand := NVL(rec_CurrCalc.black_daydemand,0);
    
    SELECT  SUM(rsp.quantity)
    INTO  rec_CurrCalc.galv_daydemand
    FROM  reco_truckstop_parts rsp,
          reco_truck rs,
          reco_rstx_originvqty roiq
    WHERE rs.truck_id = rsp.stop_truck_id
    AND rsp.orig_subinventory_code IN ('RSTX')
    AND rs.truck_status IN ('A','H','B')
    AND rs.truck_date
            >= TRUNC(oTheShipmentDemand(collCtr).thedate)
    AND rs.truck_date
            < TRUNC(oTheShipmentDemand(collCtr).thedate) + 1
    AND rsp.part_id = roiq.inventory_item_id
    AND roiq.segment1 LIKE
                      oTheShipmentDemand(collCtr).thepunch||
                      oTheShipmentDemand(collCtr).thetype||
                      'G'||
                      oTheShipmentDemand(collCtr).charlength;
    
    rec_CurrCalc.galv_daydemand := NVL(rec_CurrCalc.galv_daydemand,0);
    
    ----------
    -- Budget all new production.
    -- Ignore Black-to-Galvanizing conversion for now
    -- Ignore apply NoPunch-Black to All SP reqs and All DP reqs a needed
    -- Ignore raw-steel for now
    ----------
    
    IF vn_CurrGalvQtyThisRec >= rec_CurrCalc.galv_daydemand
    THEN
      rec_CurrCalc.galv_use_newcut := 0;
      vn_CurrGalvQtyThisRec :=
        vn_CurrGalvQtyThisRec - rec_CurrCalc.galv_daydemand;
    ELSIF vn_CurrGalvQtyThisRec < rec_CurrCalc.galv_daydemand
    THEN
      rec_CurrCalc.galv_use_newcut :=
        rec_CurrCalc.galv_daydemand - vn_CurrGalvQtyThisRec;
      vn_CurrGalvQtyThisRec := 0;
    END IF;
    
    IF vn_CurrBlackQtyThisRec >= rec_CurrCalc.black_daydemand
    THEN
      rec_CurrCalc.black_use_newcut := 0;
      vn_CurrBlackQtyThisRec :=
        vn_CurrBlackQtyThisRec - rec_CurrCalc.black_daydemand;
    ELSIF vn_CurrBlackQtyThisRec < rec_CurrCalc.black_daydemand
    THEN
      rec_CurrCalc.black_use_newcut :=
        rec_CurrCalc.black_daydemand - vn_CurrBlackQtyThisRec;
      vn_CurrBlackQtyThisRec := 0;
    END IF;
    
    ----------
    -- Apply Black-to-Galvanized conversion for galvanzied demand
    ----------
    
    rec_CurrCalc.galv_convfromblk := 0;
    
    IF rec_CurrCalc.galv_use_newcut <= vn_CurrBlackQtyThisRec
    THEN
      rec_CurrCalc.galv_convfromblk := rec_CurrCalc.galv_use_newcut;
      vn_CurrBlackQtyThisRec :=
        vn_CurrBlackQtyThisRec - rec_CurrCalc.galv_use_newcut;
      rec_CurrCalc.galv_use_newcut := 0;
    ELSIF rec_CurrCalc.galv_use_newcut > vn_CurrBlackQtyThisRec
    THEN
      rec_CurrCalc.galv_convfromblk := vn_CurrBlackQtyThisRec;
      rec_CurrCalc.galv_use_newcut :=
        rec_CurrCalc.galv_use_newcut - vn_CurrBlackQtyThisRec;
      vn_CurrBlackQtyThisRec := 0;
    END IF;
    
    ----------
    -- Apply NoPunch-Black to All SP reqs and All DP reqs a needed
    -- (the conv-black-to-galv for NoPunch was already handled above)
    ----------
    
    IF oTheShipmentDemand(collCtr).thepunch = 'S'
    OR oTheShipmentDemand(collCtr).thepunch = 'D'
    THEN
      IF rec_CurrCalc.galv_use_newcut <= vn_CurrentQtyNPB
      THEN
        vn_CurrentQtyNPB :=
          vn_CurrentQtyNPB - rec_CurrCalc.galv_use_newcut;
        rec_CurrCalc.galv_use_newcut := 0;
      ELSIF rec_CurrCalc.galv_use_newcut > vn_CurrentQtyNPB
      THEN
        rec_CurrCalc.galv_use_newcut :=
          rec_CurrCalc.galv_use_newcut - vn_CurrentQtyNPB;
        vn_CurrentQtyNPB := 0;
      END IF;
      
      IF rec_CurrCalc.black_use_newcut <= vn_CurrentQtyNPB
      THEN
        vn_CurrentQtyNPB :=
          vn_CurrentQtyNPB - rec_CurrCalc.black_use_newcut;
        rec_CurrCalc.black_use_newcut := 0;
      ELSIF rec_CurrCalc.black_use_newcut > vn_CurrentQtyNPB
      THEN
        rec_CurrCalc.black_use_newcut :=
          rec_CurrCalc.black_use_newcut - vn_CurrentQtyNPB;
        vn_CurrentQtyNPB := 0;
      END IF;
    END IF;
    
    ----------
    -- Apply any available raw steel to alleviate demand
    ----------
    
    rec_CurrCalc.galv_use_rawstl := 0;
    rec_CurrCalc.black_use_rawstl := 0;
    
    ---- CONTINUE HERE RAWSTL REMOVED
    -- It's easy to re-apply, just follow template for NP->(B/G) above
    
    ----------
    -- Now we know everthing for this specific punch on
    -- this day/length/type.
    -- 
    -- We are done preparing the one record for reco_rstx_cutreqcalc,
    -- but don't forget to update our running inventory totals
    ----------
    
    IF oTheShipmentDemand(collCtr).thepunch = 'N'
    THEN
      vn_CurrentQtyNPB := vn_CurrBlackQtyThisRec;
      vn_CurrentQtyNPG := vn_CurrGalvQtyThisRec;
    ELSIF oTheShipmentDemand(collCtr).thepunch = 'S'
    THEN
      vn_CurrentQtySPB := vn_CurrBlackQtyThisRec;
      vn_CurrentQtySPG := vn_CurrGalvQtyThisRec;
    ELSIF oTheShipmentDemand(collCtr).thepunch = 'D'
    THEN
      vn_CurrentQtyDPB := vn_CurrBlackQtyThisRec;
      vn_CurrentQtyDPG := vn_CurrGalvQtyThisRec;
    END IF;
    
    INSERT INTO reco_rstx_cutreqcalc
      (thedate,thelength,thetype,thepunch,
        rawsteel_start_inv,
        black_daystart_inv,black_daydemand,
        black_use_rawstl,black_use_newcut,
        galv_daystart_inv,galv_daydemand,
        galv_use_rawstl,galv_use_newcut,galv_convfromblk)
    VALUES
      ( rec_CurrCalc.thedate,
        rec_CurrCalc.thelength,
        rec_CurrCalc.thetype,
        rec_CurrCalc.thepunch,
        rec_CurrCalc.rawsteel_start_inv,
        rec_CurrCalc.black_daystart_inv,
        rec_CurrCalc.black_daydemand,
        rec_CurrCalc.black_use_rawstl,
        rec_CurrCalc.black_use_newcut,
        rec_CurrCalc.galv_daystart_inv,
        rec_CurrCalc.galv_daydemand,
        rec_CurrCalc.galv_use_rawstl,
        rec_CurrCalc.galv_use_newcut,
        rec_CurrCalc.galv_convfromblk);
    
  END LOOP;
  
  DELETE FROM reco_rstx_cutreqv2;
  
  INSERT INTO reco_rstx_cutreqv2
    (cutreq_id,
      reqdate,reqlength,reqtype,reqpunch,
      qty_req_black, qty_req_galv,
      qty_done_convbtog,
      qty_done_black_fromrawstl, qty_done_galv_fromrawstl,
      tot_qty_req,
      creation_date,created_by,last_update_date,last_updated_by,last_update_login)
  SELECT  reco_rstx_cutreqv2_seq.nextval,
          thedate,thelength,thetype,thepunch,
          black_use_newcut,galv_use_newcut,
          galv_convfromblk,
          black_use_rawstl,galv_use_rawstl,
          ( black_use_newcut + galv_use_newcut ),
          SYSDATE,-1,SYSDATE,-1,-1
  FROM
    (
      SELECT  thedate,thelength,thetype,thepunch,
              rawsteel_start_inv,
              black_daystart_inv,black_daydemand,
              black_use_rawstl,black_use_newcut,
              galv_daystart_inv,galv_daydemand,
              galv_use_rawstl,galv_use_newcut,galv_convfromblk,
              CASE
              WHEN thepunch = 'N'
              THEN 1
              WHEN thepunch = 'D'
              THEN 2
              WHEN thepunch = 'S'
              THEN 3
              ELSE 4
              END thesortord
      FROM reco_rstx_cutreqcalc
      WHERE   black_use_newcut > 0
      OR      galv_use_newcut > 0
      OR      galv_convfromblk > 0
      OR      black_use_rawstl > 0
      OR      galv_use_rawstl > 0
      ORDER BY  TRUNC(thedate),
                thelength desc, -- Always analyze longer before shorter
                thetype,
                CASE
                WHEN thepunch = 'N'
                THEN 1
                WHEN thepunch = 'D'
                THEN 2
                WHEN thepunch = 'S'
                THEN 3
                ELSE 4
                END
    );
  
END;  -- setup_cut_requirements

----------------------------------------------------------
-- setup_cutmtx_allowed_lenpuns
-- 
-- This serves as a filter for which cutmatrixes are
-- allowed for the whole process.
-- 
-- Why is this needed?
-- Because this also filters PUNCH, which is not handled
-- in the reco_rstx_cutmtx tables
-- 
-- So this must contain approved matrices that
-- include LENGTH allowed and PUNCH allowed
-- (e.g. We can allow  32(DP)-16(SP) and
--       we can forbid 32(SP)-16(SP)    )
-- 
-- This also contains PART_TYPE so you can theoretically
-- setup filter based on parttype (504, 506, etc ...)
-- 
-- AT A MINIMUM, you should include cut/len/pun matrixes
-- to satisfy each requirement in reco_rstx_cutreq table
-- (and account for the other/extra pieces on the bar)
-- 
-- PRE-CONDITIONS
-- : clear_existing_reqsandplans
-- : validate_and_count_inv should have completed successfully
--   (it should have returned 'DONE' message)
-- : setup_cut_requirements should have completed successfully
PROCEDURE setup_cutmtx_allowed_lenpuns
IS
BEGIN -- setup_cutmtx_allowed_lenpuns
  DELETE FROM reco_rstx_cutmtx_lenpunmap;
  
  INSERT INTO reco_rstx_cutmtx_lenpunmap
    (thelength, thetype, thepunch)
  (
    SELECT DISTINCT cutpce.unit_volume, cutmtx.ptype, 'S'
    FROM reco_rstx_cutmtx cutmtx, reco_rstx_cutpce cutpce
    WHERE cutmtx.cutmtx_id = cutpce.cutmtx_id
    AND cutpce.piece_number = 1
  );
  
  INSERT INTO reco_rstx_cutmtx_lenpunmap
    (thelength, thetype, thepunch)
  (
    SELECT DISTINCT
            cutreq.reqlength,
            cutreq.reqtype,
            cutreq.reqpunch
    FROM reco_rstx_cutreqv2 cutreq
    WHERE cutreq.reqpunch != 'S'
    AND (cutreq.qty_req_black > 0 OR cutreq.qty_req_galv > 0)
  );
END; -- setup_cutmtx_allowed_lenpuns

----------------------------------------------------------
-- Take given parameters, and apply to all the rstx
-- tables, including:
-- : reco_rstx_cutrun
-- : reco_rstx_cutasg
-- : reco_rstx_cutovg
-- : reco_rstx_day_pkt_bin
-- : reco_rstx_run_placement
-- 
-- As always, we can assume that the given pocket size
-- exists, and is completely empty.
-- So we just take this whole cut run and place it into
-- a single pocket
-- 
-- This does not set any first_machine_label and
-- last_machine_label, so that is left to the caller
PROCEDURE apply_matrix_to_reqs (
                pi_CurrentPartType IN varchar2,
                pi_CurrentCutDate IN date,
                pi_GivenQtyBars IN number,
                pi_GivenPktSize IN number,
                pi_MtxQtyPcs IN number,
                pi_MtxPc1Len IN reco_rstx_cutreqv2.reqlength%TYPE,
                pi_MtxPc1Pun IN reco_rstx_cutreqv2.reqpunch%TYPE,
                pi_MtxPc2Len IN reco_rstx_cutreqv2.reqlength%TYPE,
                pi_MtxPc2Pun IN reco_rstx_cutreqv2.reqpunch%TYPE,
                pi_MtxPc3Len IN reco_rstx_cutreqv2.reqlength%TYPE,
                pi_MtxPc3Pun IN reco_rstx_cutreqv2.reqpunch%TYPE,
                pi_MtxPc4Len IN reco_rstx_cutreqv2.reqlength%TYPE,
                pi_MtxPc4Pun IN reco_rstx_cutreqv2.reqpunch%TYPE)
IS
  vn_CutMtxId number;
  vn_DayPocketId number;
  vn_RunNumber number;
  
  -- This object must be used for application
  -- 
  -- After picking the cutmtx_id, then you cannot use pi_Mtx items again
  -- You must use the "correctly sorted / mapped" object
  
  TYPE rec_FinalMtx
  IS record ( cutmtxid reco_rstx_cutmtx.cutmtx_id%TYPE,
              mtxPce1TblId reco_rstx_cutpce.cutpce_id%TYPE,
              mtxPce1Len reco_rstx_cutpce.unit_volume%TYPE,
              mtxPce1Pun reco_rstx_cutreqv2.reqpunch%TYPE,
              mtxPce2TblId reco_rstx_cutpce.cutpce_id%TYPE,
              mtxPce2Len reco_rstx_cutpce.unit_volume%TYPE,
              mtxPce2Pun reco_rstx_cutreqv2.reqpunch%TYPE,
              mtxPce3TblId reco_rstx_cutpce.cutpce_id%TYPE,
              mtxPce3Len reco_rstx_cutpce.unit_volume%TYPE,
              mtxPce3Pun reco_rstx_cutreqv2.reqpunch%TYPE,
              mtxPce4TblId reco_rstx_cutpce.cutpce_id%TYPE,
              mtxPce4Len reco_rstx_cutpce.unit_volume%TYPE,
              mtxPce4Pun reco_rstx_cutreqv2.reqpunch%TYPE);
  
  oFinalMtx rec_FinalMtx;
  
BEGIN -- apply_matrix_to_reqs
  
  ---
  -- Select a cut matrix which includes all the lengths given
  -- 
  -- NOTE: This does not match the PieceNumber to ParameterNumber
  --       So if the given input is:
  --          : pi1=18' and pi2=30'
  --       then it is possible to select a matrix 
  --          : pi1=30' and pi2=18'
  -- 
  -- >>> It maybe backwards/mixed order <<<
  -- 
  -- After this step,
  -- then we need to match the input's LENGTH/PUNCH order
  -- to the select matrix's LENGTH/PUNCH order
  ---
  
  IF pi_MtxQtyPcs = 2
  THEN
    SELECT cutmtx_id INTO vn_CutMtxId
    FROM
    (
      SELECT ROWNUM therownum, cutmtx_id
      FROM
      (
        SELECT  cutmtx.cutmtx_id
        FROM  reco_rstx_cutmtx cutmtx,
              reco_rstx_cutpce cutpce1,
              reco_rstx_cutpce cutpce2
        WHERE   cutmtx.qty_pieces_made = pi_MtxQtyPcs
        AND     cutmtx.ptype = pi_CurrentPartType
        AND     cutmtx.cutmtx_id = cutpce1.cutmtx_id
        AND     cutpce1.unit_volume = pi_MtxPc1Len
        AND     cutmtx.cutmtx_id = cutpce2.cutmtx_id
        AND     cutpce2.unit_volume = pi_MtxPc2Len
        AND     cutpce1.cutpce_id != cutpce2.cutpce_id
      )
    )
    WHERE therownum = 1;
  ELSIF pi_MtxQtyPcs = 3
  THEN
    SELECT cutmtx_id INTO vn_CutMtxId
    FROM
    (
      SELECT ROWNUM therownum, cutmtx_id
      FROM
      (
        SELECT  cutmtx.cutmtx_id
        FROM  reco_rstx_cutmtx cutmtx,
              reco_rstx_cutpce cutpce1,
              reco_rstx_cutpce cutpce2,
              reco_rstx_cutpce cutpce3
        WHERE   cutmtx.qty_pieces_made = pi_MtxQtyPcs
        AND     cutmtx.ptype = pi_CurrentPartType
        AND     cutmtx.cutmtx_id = cutpce1.cutmtx_id
        AND     cutpce1.unit_volume = pi_MtxPc1Len
        AND     cutmtx.cutmtx_id = cutpce2.cutmtx_id
        AND     cutpce2.unit_volume = pi_MtxPc2Len
        AND     cutmtx.cutmtx_id = cutpce3.cutmtx_id
        AND     cutpce3.unit_volume = pi_MtxPc3Len
        AND     cutpce1.cutpce_id != cutpce2.cutpce_id
        AND     cutpce1.cutpce_id != cutpce3.cutpce_id
        AND     cutpce2.cutpce_id != cutpce3.cutpce_id
      )
    )
    WHERE therownum = 1;
  ELSIF pi_MtxQtyPcs = 4
  THEN
    SELECT cutmtx_id INTO vn_CutMtxId
    FROM
    (
      SELECT ROWNUM therownum, cutmtx_id
      FROM
      (
        SELECT  cutmtx.cutmtx_id
        FROM  reco_rstx_cutmtx cutmtx,
              reco_rstx_cutpce cutpce1,
              reco_rstx_cutpce cutpce2,
              reco_rstx_cutpce cutpce3,
              reco_rstx_cutpce cutpce4
        WHERE   cutmtx.qty_pieces_made = pi_MtxQtyPcs
        AND     cutmtx.ptype = pi_CurrentPartType
        AND     cutmtx.cutmtx_id = cutpce1.cutmtx_id
        AND     cutpce1.unit_volume = pi_MtxPc1Len
        AND     cutmtx.cutmtx_id = cutpce2.cutmtx_id
        AND     cutpce2.unit_volume = pi_MtxPc2Len
        AND     cutmtx.cutmtx_id = cutpce3.cutmtx_id
        AND     cutpce3.unit_volume = pi_MtxPc3Len
        AND     cutmtx.cutmtx_id = cutpce4.cutmtx_id
        AND     cutpce4.unit_volume = pi_MtxPc4Len
        AND     cutpce1.cutpce_id != cutpce2.cutpce_id
        AND     cutpce1.cutpce_id != cutpce3.cutpce_id
        AND     cutpce1.cutpce_id != cutpce4.cutpce_id
        AND     cutpce2.cutpce_id != cutpce3.cutpce_id
        AND     cutpce2.cutpce_id != cutpce4.cutpce_id
        AND     cutpce3.cutpce_id != cutpce4.cutpce_id
      )
    )
    WHERE therownum = 1;
  END IF;
  
  ---
  -- Take the cutmtx_id that we selected
  -- and we can fill out most of the info into our final item
  -- (based on the cutmtx table)
  -- Do NOT use the parameters here
  ---
  
  SELECT  cutmtx.cutmtx_id,
          cutpce1.cutpce_id,
          cutpce1.unit_volume mtxPce1Len,
          NULL mtxPce1Pun,
          cutpce2.cutpce_id,
          cutpce2.unit_volume mtxPce2Len,
          NULL mtxPce2Pun,
          cutpce3.cutpce_id,
          cutpce3.unit_volume mtxPce3Len,
          NULL mtxPce3Pun,
          cutpce4.cutpce_id,
          cutpce4.unit_volume mtxPce4Len,
          NULL mtxPce4Pun
  INTO oFinalMtx
  FROM  reco_rstx_cutmtx cutmtx,
        reco_rstx_cutpce cutpce1,
        reco_rstx_cutpce cutpce2,
        reco_rstx_cutpce cutpce3,
        reco_rstx_cutpce cutpce4
  WHERE   vn_CutMtxId = cutmtx.cutmtx_id
  AND     cutmtx.cutmtx_id = cutpce1.cutmtx_id (+)
  AND     cutpce1.piece_number (+) = 1
  AND     cutmtx.cutmtx_id = cutpce2.cutmtx_id (+)
  AND     cutpce2.piece_number (+) = 2
  AND     cutmtx.cutmtx_id = cutpce3.cutmtx_id (+)
  AND     cutpce3.piece_number (+) = 3
  AND     cutmtx.cutmtx_id = cutpce4.cutmtx_id (+)
  AND     cutpce4.piece_number (+) = 4;
  
  ---
  -- We have selected a matrix, for example:
  --     14 - 16 - 18
  -- 
  -- However, the given parameters might be:
  --     DP18 - DP16 - SP14
  -- 
  -- See the problem?
  -- The input parameters pi_MtxPc2Len / pi_MtxPc4Pun
  -- May not reflect the exact length/punch order of the selected matrix
  -- 
  -- So we cannot use pi_MtxPc1Len / pi_MtxPc2Pun after this point
  ---
  
  DECLARE
    vb_Param1AlreadyUsed BOOLEAN;
    vb_Param2AlreadyUsed BOOLEAN;
    vb_Param3AlreadyUsed BOOLEAN;
    vb_Param4AlreadyUsed BOOLEAN;
  BEGIN
    vb_Param1AlreadyUsed := FALSE;
    vb_Param2AlreadyUsed := FALSE;
    vb_Param3AlreadyUsed := FALSE;
    vb_Param4AlreadyUsed := FALSE;
    
    IF pi_MtxQtyPcs >= 1
    THEN
      IF pi_MtxQtyPcs >= 1 AND oFinalMtx.mtxPce1Len = pi_MtxPc1Len
      AND vb_Param1AlreadyUsed = FALSE
      THEN
        vb_Param1AlreadyUsed := TRUE;
        oFinalMtx.mtxPce1Pun := pi_MtxPc1Pun;
      ELSIF pi_MtxQtyPcs >= 2 AND oFinalMtx.mtxPce1Len = pi_MtxPc2Len
      AND vb_Param2AlreadyUsed = FALSE
      THEN
        vb_Param2AlreadyUsed := TRUE;
        oFinalMtx.mtxPce1Pun := pi_MtxPc2Pun;
      ELSIF pi_MtxQtyPcs >= 3 AND oFinalMtx.mtxPce1Len = pi_MtxPc3Len
      AND vb_Param3AlreadyUsed = FALSE
      THEN
        vb_Param3AlreadyUsed := TRUE;
        oFinalMtx.mtxPce1Pun := pi_MtxPc3Pun;
      ELSIF pi_MtxQtyPcs >= 4 AND oFinalMtx.mtxPce1Len = pi_MtxPc4Len
      AND vb_Param4AlreadyUsed = FALSE
      THEN
        vb_Param4AlreadyUsed := TRUE;
        oFinalMtx.mtxPce1Pun := pi_MtxPc4Pun;
      ELSE
        -- Internal Error.
        -- But Apply_Matrix_To_Reqs lacks error handling at this point
        NULL;
      END IF;
    END IF;
    
    IF pi_MtxQtyPcs >= 2
    THEN
      IF pi_MtxQtyPcs >= 1 AND oFinalMtx.mtxPce2Len = pi_MtxPc1Len
      AND vb_Param1AlreadyUsed = FALSE
      THEN
        vb_Param1AlreadyUsed := TRUE;
        oFinalMtx.mtxPce2Pun := pi_MtxPc1Pun;
      ELSIF pi_MtxQtyPcs >= 2 AND oFinalMtx.mtxPce2Len = pi_MtxPc2Len
      AND vb_Param2AlreadyUsed = FALSE
      THEN
        vb_Param2AlreadyUsed := TRUE;
        oFinalMtx.mtxPce2Pun := pi_MtxPc2Pun;
      ELSIF pi_MtxQtyPcs >= 3 AND oFinalMtx.mtxPce2Len = pi_MtxPc3Len
      AND vb_Param3AlreadyUsed = FALSE
      THEN
        vb_Param3AlreadyUsed := TRUE;
        oFinalMtx.mtxPce2Pun := pi_MtxPc3Pun;
      ELSIF pi_MtxQtyPcs >= 4 AND oFinalMtx.mtxPce2Len = pi_MtxPc4Len
      AND vb_Param4AlreadyUsed = FALSE
      THEN
        vb_Param4AlreadyUsed := TRUE;
        oFinalMtx.mtxPce2Pun := pi_MtxPc4Pun;
      ELSE
        -- Internal Error.
        -- But Apply_Matrix_To_Reqs lacks error handling at this point
        NULL;
      END IF;
    END IF;
    
    IF pi_MtxQtyPcs >= 3
    THEN
      IF pi_MtxQtyPcs >= 1 AND oFinalMtx.mtxPce3Len = pi_MtxPc1Len
      AND vb_Param1AlreadyUsed = FALSE
      THEN
        vb_Param1AlreadyUsed := TRUE;
        oFinalMtx.mtxPce3Pun := pi_MtxPc1Pun;
      ELSIF pi_MtxQtyPcs >= 2 AND oFinalMtx.mtxPce3Len = pi_MtxPc2Len
      AND vb_Param2AlreadyUsed = FALSE
      THEN
        vb_Param2AlreadyUsed := TRUE;
        oFinalMtx.mtxPce3Pun := pi_MtxPc2Pun;
      ELSIF pi_MtxQtyPcs >= 3 AND oFinalMtx.mtxPce3Len = pi_MtxPc3Len
      AND vb_Param3AlreadyUsed = FALSE
      THEN
        vb_Param3AlreadyUsed := TRUE;
        oFinalMtx.mtxPce3Pun := pi_MtxPc3Pun;
      ELSIF pi_MtxQtyPcs >= 4 AND oFinalMtx.mtxPce3Len = pi_MtxPc4Len
      AND vb_Param4AlreadyUsed = FALSE
      THEN
        vb_Param4AlreadyUsed := TRUE;
        oFinalMtx.mtxPce3Pun := pi_MtxPc4Pun;
      ELSE
        -- Internal Error.
        -- But Apply_Matrix_To_Reqs lacks error handling at this point
        NULL;
      END IF;
    END IF;
    
    IF pi_MtxQtyPcs >= 4
    THEN
      IF pi_MtxQtyPcs >= 1 AND oFinalMtx.mtxPce4Len = pi_MtxPc1Len
      AND vb_Param1AlreadyUsed = FALSE
      THEN
        vb_Param1AlreadyUsed := TRUE;
        oFinalMtx.mtxPce4Pun := pi_MtxPc1Pun;
      ELSIF pi_MtxQtyPcs >= 2 AND oFinalMtx.mtxPce4Len = pi_MtxPc2Len
      AND vb_Param2AlreadyUsed = FALSE
      THEN
        vb_Param2AlreadyUsed := TRUE;
        oFinalMtx.mtxPce4Pun := pi_MtxPc2Pun;
      ELSIF pi_MtxQtyPcs >= 3 AND oFinalMtx.mtxPce4Len = pi_MtxPc3Len
      AND vb_Param3AlreadyUsed = FALSE
      THEN
        vb_Param3AlreadyUsed := TRUE;
        oFinalMtx.mtxPce4Pun := pi_MtxPc3Pun;
      ELSIF pi_MtxQtyPcs >= 4 AND oFinalMtx.mtxPce4Len = pi_MtxPc4Len
      AND vb_Param4AlreadyUsed = FALSE
      THEN
        vb_Param4AlreadyUsed := TRUE;
        oFinalMtx.mtxPce4Pun := pi_MtxPc4Pun;
      ELSE
        -- Internal Error.
        -- But Apply_Matrix_To_Reqs lacks error handling at this point
        NULL;
      END IF;
    END IF;
  END;
  
  ---
  -- Select a pocket for the given qty-pieces
  ---
  
  SELECT day_pocket_id INTO vn_DayPocketId
  FROM
  (
    SELECT ROWNUM therownum, day_pocket_id, pocket_number
    FROM
    (
      SELECT  daypocket.day_pocket_id, daypocket.pocket_number
      FROM  reco_rstx_calday calday, reco_rstx_day_pocket daypocket
      WHERE   calday.calday_id = daypocket.calday_id
      AND     calday.thedate = pi_CurrentCutDate
      AND     daypocket.parttype = pi_CurrentPartType
      AND     daypocket.storage_capacity = pi_GivenPktSize
      AND NOT EXISTS (SELECT 1 FROM reco_rstx_day_pkt_bin subBins
                      WHERE subBins.day_pocket_id = daypocket.day_pocket_id)
      ORDER BY daypocket.pocket_number desc
    )
  )
  WHERE therownum = 1;
  
  ---
  -- Figure out the run_number
  ---
  
  SELECT MAX(run_number) INTO vn_RunNumber FROM reco_rstx_cutrun;
  
  IF vn_RunNumber IS NULL THEN vn_RunNumber := 1;
  ELSIF vn_RunNumber IS NOT NULL THEN vn_RunNumber := vn_RunNumber + 1;
  END IF;
  
  FOR piecectr IN 1 .. pi_MtxQtyPcs -- loop for each piece
  LOOP
    DECLARE
      vn_CurrCutPceId number;
      vn_CurrUnitVolume reco_rstx_cutreqv2.reqlength%TYPE;
      vc_CurrPiecePunch reco_rstx_cutreqv2.reqpunch%TYPE;
      
      vr_cutrun reco_rstx_cutrun%ROWTYPE;
      vr_daypktbin reco_rstx_day_pkt_bin%ROWTYPE;
      
      vn_CurrApplyQty number;
    BEGIN
      
      -- NOTE: Do not use pi_MtxPc Paramaters here
      
      IF piecectr = 1
      THEN
        vn_CurrCutPceId := oFinalMtx.mtxPce1TblId;
        vn_CurrUnitVolume := oFinalMtx.mtxPce1Len;
        vc_CurrPiecePunch := oFinalMtx.mtxPce1Pun;
      ELSIF piecectr = 2
      THEN
        vn_CurrCutPceId := oFinalMtx.mtxPce2TblId;
        vn_CurrUnitVolume := oFinalMtx.mtxPce2Len;
        vc_CurrPiecePunch := oFinalMtx.mtxPce2Pun;
      ELSIF piecectr = 3
      THEN
        vn_CurrCutPceId := oFinalMtx.mtxPce3TblId;
        vn_CurrUnitVolume := oFinalMtx.mtxPce3Len;
        vc_CurrPiecePunch := oFinalMtx.mtxPce3Pun;
      ELSIF piecectr = 4
      THEN
        vn_CurrCutPceId := oFinalMtx.mtxPce4TblId;
        vn_CurrUnitVolume := oFinalMtx.mtxPce4Len;
        vc_CurrPiecePunch := oFinalMtx.mtxPce4Pun;
      END IF;
      
      SELECT reco_rstx_cutrun_seq.nextval
      INTO vr_cutrun.cutrun_id FROM dual;
      
      vr_cutrun.run_number := vn_RunNumber;
      
      vr_cutrun.cutpce_id := vn_CurrCutPceId;
      
      vr_cutrun.qty_bars_processed := pi_GivenQtyBars;
      
      SELECT reco_rstx_day_pkt_bin_seq.nextval
      INTO vr_daypktbin.day_pkt_bin_id FROM dual;
      
      vr_daypktbin.day_pocket_id := vn_DayPocketId;
      
      vr_daypktbin.length_of_part := vn_CurrUnitVolume;
      
      vr_daypktbin.length_used := vn_CurrUnitVolume;
      IF MOD(vn_CurrUnitVolume,2) = 1
      THEN vr_daypktbin.length_used := vn_CurrUnitVolume + 1;
      END IF;
      
      vr_daypktbin.first_machine_label := NULL; -- Set later via set_bin_labels
      
      vr_daypktbin.last_machine_label := NULL; -- Set later via set_bin_labels
      
      INSERT INTO reco_rstx_cutrun
        (cutrun_id,run_number,cutpce_id,qty_bars_processed,
          last_update_date,last_updated_by,last_update_login,
          creation_date,created_by )
      VALUES
        (vr_cutrun.cutrun_id,vr_cutrun.run_number,vr_cutrun.cutpce_id,
          vr_cutrun.qty_bars_processed,SYSDATE,-1,-1,SYSDATE,-1);
      
      INSERT INTO reco_rstx_day_pkt_bin
        (day_pkt_bin_id,day_pocket_id,length_of_part,length_used,
          first_machine_label,last_machine_label,
          last_update_date,last_updated_by,last_update_login,
          creation_date,created_by )
      VALUES
        (vr_daypktbin.day_pkt_bin_id, vr_daypktbin.day_pocket_id,
          vr_daypktbin.length_of_part, vr_daypktbin.length_used,
          vr_daypktbin.first_machine_label, vr_daypktbin.last_machine_label,
          SYSDATE,-1,-1,SYSDATE,-1);
      
      INSERT INTO reco_rstx_run_placement
        (placement_id,cutrun_id,day_pkt_bin_id,qty_placed,
          last_update_date,last_updated_by,last_update_login,
          creation_date,created_by)
      SELECT reco_rstx_run_placement_seq.nextval,
        vr_cutrun.cutrun_id,vr_daypktbin.day_pkt_bin_id,
        vr_cutrun.qty_bars_processed,SYSDATE,-1,-1,SYSDATE,-1
      FROM dual;
      
      vn_CurrApplyQty := pi_GivenQtyBars;
      
      ---
      -- We added the reco_rstx_cutrun entry and also
      -- entries for reco_rstx_run_placement and reco_rstx_day_pkt_bin
      -- 
      -- So now we need to actually map/tieback the run to
      -- reco_rstx_cutreqv2 table
      ---
      
      DECLARE
        -- Use a cursor and collection because we want to FETCH ALL the
        -- remaining requirements BEFORE we start updating requirements
        
        CURSOR cur_Remaining
        IS
          SELECT  reqQ.cutreq_id,
                  reqQ.reqdate,
                  (reqQ.qty_req_black-NVL(asgQ.totasg_b,0)) qty_remain_black,
                  (reqQ.qty_req_galv-NVL(asgQ.totasg_g,0)) qty_remain_galv
          FROM  (
                  SELECT  subreq.cutreq_id,
                          subreq.reqdate,
                          subreq.qty_req_black,
                          subreq.qty_req_galv
                  FROM  reco_rstx_cutreqv2 subreq
                  WHERE   subreq.reqtype = pi_CurrentPartType
                  AND     subreq.reqlength = vn_CurrUnitVolume
                  AND     subreq.reqpunch = vc_CurrPiecePunch
                ) reqQ,
                (
                  SELECT  subreq.cutreq_id,
                          SUM(subasg.qty_asg_black) totasg_b,
                          SUM(subasg.qty_asg_galv) totasg_g
                  FROM  reco_rstx_cutreqv2 subreq, reco_rstx_cutasgv2 subasg
                  WHERE   subreq.cutreq_id = subasg.cutreq_id
                  AND     subreq.reqtype = pi_CurrentPartType
                  AND     subreq.reqlength = vn_CurrUnitVolume
                  AND     subreq.reqpunch = vc_CurrPiecePunch
                  GROUP BY  subreq.cutreq_id
                ) asgQ
          WHERE   reqQ.cutreq_id = asgQ.cutreq_id (+)
          AND     ( reqQ.qty_req_black > NVL(asgQ.totasg_b,0) OR
                    reqQ.qty_req_galv > NVL(asgQ.totasg_g,0))
          ORDER BY    reqQ.reqdate;
        
        TYPE coll_Remaining IS TABLE OF cur_Remaining%ROWTYPE;
        
        oTheRemaining coll_Remaining; -- Fetched, so don't initialize
        --oTheRemaining coll_Remaining := coll_Remaining();
                                        -- Initialize since not fetched
        
        vr_cutasg reco_rstx_cutasgv2%ROWTYPE;
        
      BEGIN
        OPEN cur_Remaining;
        FETCH cur_Remaining BULK COLLECT INTO oTheRemaining;
        CLOSE cur_Remaining;
        
        FOR nCtrRemaining IN 1 .. oTheRemaining.count
        LOOP
          SELECT reco_rstx_cutasgv2_seq.nextval
          INTO vr_cutasg.cutasg_id FROM dual;
          
          vr_cutasg.cutrun_id := vr_cutrun.cutrun_id;
          
          vr_cutasg.cutreq_id := oTheRemaining(nCtrRemaining).cutreq_id;
          
          vr_cutasg.qty_asg_galv := vn_CurrApplyQty;
          IF vr_cutasg.qty_asg_galv
                    > oTheRemaining(nCtrRemaining).qty_remain_galv
          THEN
            vr_cutasg.qty_asg_galv :=
                oTheRemaining(nCtrRemaining).qty_remain_galv;
          END IF;
          vn_CurrApplyQty := vn_CurrApplyQty - vr_cutasg.qty_asg_galv;
          
          vr_cutasg.qty_asg_black := vn_CurrApplyQty;
          IF vr_cutasg.qty_asg_black
                    > oTheRemaining(nCtrRemaining).qty_remain_black
          THEN
            vr_cutasg.qty_asg_black :=
                oTheRemaining(nCtrRemaining).qty_remain_black;
          END IF;
          vn_CurrApplyQty := vn_CurrApplyQty - vr_cutasg.qty_asg_black;
          
          INSERT INTO reco_rstx_cutasgv2
            (cutasg_id,
              cutrun_id,cutreq_id,
              qty_asg_black,qty_asg_galv,
              last_update_date,last_updated_by,last_update_login,
              creation_date,created_by)
          VALUES
            (vr_cutasg.cutasg_id,
              vr_cutasg.cutrun_id,vr_cutasg.cutreq_id,
              vr_cutasg.qty_asg_black,vr_cutasg.qty_asg_galv,
              SYSDATE,-1,-1,SYSDATE,-1);
          
          IF vn_CurrApplyQty = 0
          THEN exit;
          END IF;
        END LOOP;
      END;
      
      IF vn_CurrApplyQty > 0
      THEN
        INSERT INTO reco_rstx_cutovg
          (cutovg_id,cutrun_id,overage_qty,last_update_date,
            last_updated_by,last_update_login,creation_date,created_by)
        SELECT reco_rstx_cutovg_seq.nextval,vr_cutrun.cutrun_id,
          vn_CurrApplyQty,SYSDATE,-1,-1,SYSDATE,-1
        FROM dual;
      END IF;
    END;
  END LOOP; -- loop for each piece
END; -- apply_matrix_to_reqs

--------------------------------------------------------------------------------
-- fill_rarelen_reqs
-- 
-- These items are given: CutDate/PartType/PocketsAvailable,
-- we grab each empty pocket available and assign some cut matrix to it,
-- and this only applies to rare lengths that we find
-- 
-- POST-CONDITIONS
-- : runs 'DONE' when successful, or an error message when problems occur
FUNCTION fill_rarelen_reqs( pi_GivenRawBarSize IN number,
                            pi_CurrentPartType IN varchar2,
                            pi_CurrentCutDate IN date,
                            pi_MinimumPceSize IN number,
                            pi_MaximumPceSize IN number,
                            pi_rare_length_days_out IN number)
RETURN varchar2
IS
  vd_LastDateOfRareLens date;
  
  vn_MinPocketCapacity number;
  vn_MaxPocketCapacity number;
  
  vn_MaxBars number;
  vn_QtyBarsPerRun number;
  
  vn_CurrentBarQtyInDate number;
  
  TYPE rec_RareLenReq IS record (
                thelength reco_rstx_cutreqv2.reqlength%TYPE,
                thepunch reco_rstx_cutreqv2.reqpunch%TYPE,
                theqtyreq number);
  TYPE coll_RareLenReqs IS TABLE OF rec_RareLenReq;
  
  oTheRareLenReqs coll_RareLenReqs; -- Fetched, so don't initialize
  --oTheRareLenReqs coll_RareLenReqs := coll_RareLenReqs();
  --                                    -- Initialize since not fetched
  
  TYPE coll_PktCapacities IS TABLE OF number;
  oThePktCapacities coll_PktCapacities; -- Fetched, so don't initialize
  --oThePktCapacities coll_ReqData := coll_PktCapacities();
  --                                  -- Initialize since not fetched
  
  vc_OutputMessage varchar2(1000);
BEGIN -- fill_rarelen_reqs
  
  vc_OutputMessage := 'Error: Unkn rarelength error. Contact MIS';
  
  -----
  -- Get Business Day requirements for rare lengths
  
  SELECT thedate
  INTO vd_LastDateOfRareLens
  FROM
  (
    SELECT ROWNUM therownum, thedate
    FROM
    (
      SELECT calday.thedate
      FROM reco_rstx_calday calday
      WHERE calday.thedate > pi_CurrentCutDate
      AND calday.is_production_allowed = 'Y'
      ORDER BY calday.thedate
    )
  )
  WHERE therownum = pi_rare_length_days_out;
  
  
  -----
  -- Loop while there are pockets available for this date/parttype
  
  LOOP -- loop while empty pockets exist for us to use
    
    -----
    -- Check that rare length requirements exist for the parameters
    
    DECLARE
      vc_Temp number;
    BEGIN
      SELECT 1 INTO vc_Temp
      FROM
            (
              SELECT  SUM(subreq.tot_qty_req) totQty
              FROM  reco_rstx_cutreqv2 subreq
              WHERE   subreq.reqtype = pi_CurrentPartType
              AND     subreq.reqdate <= vd_LastDateOfRareLens
              AND     EXISTS (SELECT 1 FROM reco_rstx_rarelength rarelen
                              WHERE rarelen.unit_volume = subreq.reqlength)
            ) subQReq,
            (
              SELECT  SUM(subasg.qty_asg_black + subasg.qty_asg_galv) totQty
              FROM  reco_rstx_cutreqv2 subreq, reco_rstx_cutasgv2 subasg
              WHERE   subreq.cutreq_id = subasg.cutreq_id
              AND     subreq.reqtype = pi_CurrentPartType
              AND     subreq.reqdate <= vd_LastDateOfRareLens
              AND     EXISTS (SELECT 1 FROM reco_rstx_rarelength rarelen
                              WHERE rarelen.unit_volume = subreq.reqlength)
            ) subQAsg
      WHERE subQReq.totQty > NVL(subQAsg.totQty,0);
    EXCEPTION
      WHEN NO_DATA_FOUND
      THEN
        vc_OutputMessage := 'DONE';
        exit;
      WHEN TOO_MANY_ROWS
      THEN
        NULL;
      WHEN others
      THEN
        vc_OutputMessage := 'Intenal Error at rarelength requirements review';
        exit;
    END;
    
    -----
    -- Check that there are pockets available, and access pocket data
    
    DECLARE
      vn_TmpQueryId number;
    BEGIN
      SELECT  calday.calday_id,
              calday.qty_bars_max,
              calday.qty_bars_per_run,
              MIN(daypocket.storage_capacity) minpktsize,
              MAX(daypocket.storage_capacity) maxpktsize
      INTO  vn_TmpQueryId,
            vn_MaxBars,
            vn_QtyBarsPerRun,
            vn_MinPocketCapacity,
            vn_MaxPocketCapacity
      FROM reco_rstx_day_pocket daypocket, reco_rstx_calday calday
      WHERE daypocket.calday_id = calday.calday_id
      AND calday.thedate = pi_CurrentCutDate
      AND daypocket.parttype = pi_CurrentPartType
      AND NOT EXISTS (SELECT 1 FROM reco_rstx_day_pkt_bin subBins
                      WHERE subBins.day_pocket_id = daypocket.day_pocket_id)
      GROUP BY calday.calday_id,calday.qty_bars_max,calday.qty_bars_per_run;
    EXCEPTION
      WHEN NO_DATA_FOUND
      THEN
        vc_OutputMessage := 'DONE';
        exit;
      WHEN others
      THEN
        vc_OutputMessage := 'Intenal Error at rarelength pockets review';
        exit;
    END;
    
    -----
    -- If we have reached our daily limit, then of course we are done,
    -- regardless of how many pockets were filled
    
    SELECT SUM(qty_bars_processed) INTO vn_CurrentBarQtyInDate
    FROM  (
            SELECT DISTINCT cutrun.run_number, cutrun.qty_bars_processed
            FROM  reco_rstx_calday calday,
                  reco_rstx_day_pocket daypocket,
                  reco_rstx_day_pkt_bin daypktbin,
                  reco_rstx_run_placement placement,
                  reco_rstx_cutrun cutrun
            WHERE   calday.thedate = pi_CurrentCutDate
            AND     calday.calday_id = daypocket.calday_id
            AND     daypocket.day_pocket_id = daypktbin.day_pocket_id
            AND     daypktbin.day_pkt_bin_id = placement.day_pkt_bin_id
            AND     placement.cutrun_id = cutrun.cutrun_id
          );
    
    IF vn_CurrentBarQtyInDate IS NULL
    THEN vn_CurrentBarQtyInDate := 0;
    END IF;
    
    IF vn_CurrentBarQtyInDate >= vn_MaxBars
    THEN
      vc_OutputMessage := 'DONE';
      IF vn_CurrentBarQtyInDate > vn_MaxBars
      THEN vc_OutputMessage := 'Internal Error 2028 - Excessive cutting in day';
      END IF;
      
      exit;
    END IF;
    
    
    -----
    -- Get rare length requirements
    
    SELECT  rareItemsSubQ.thelength,
            rareItemsSubQ.thepunch,
            NVL(rareReqSubQ.qtyRemain,0)
    BULK COLLECT INTO oTheRareLenReqs
    FROM
        (
          SELECT DISTINCT
                  rarelen.unit_volume thelength,
                  lenpunmap.thepunch thepunch
          FROM  reco_rstx_rarelength rarelen,
                reco_rstx_cutmtx_lenpunmap lenpunmap
          WHERE   rarelen.unit_volume = lenpunmap.thelength
          AND     lenpunmap.thetype = pi_CurrentPartType
          AND     unit_volume >= pi_MinimumPceSize
          AND     unit_volume <= pi_MaximumPceSize
        ) rareItemsSubQ,
        (
          SELECT  subItemR.reqlength,
                  subItemR.reqpunch,
                  subItemR.totQty - NVL(subItemA.totQty,0) qtyRemain
          FROM
          (
            SELECT  subreq.reqlength,
                    subreq.reqpunch,
                    SUM(subreq.qty_req_black + subreq.qty_req_galv) totQty
            FROM  reco_rstx_cutreqv2 subreq
            WHERE   subreq.reqdate <= vd_LastDateOfRareLens
            AND     subreq.reqtype = pi_CurrentPartType
            AND     subreq.reqlength >= pi_MinimumPceSize
            AND     subreq.reqlength <= pi_MaximumPceSize
            AND     EXISTS (SELECT 1 FROM reco_rstx_rarelength rarelen
                            WHERE rarelen.unit_volume = subreq.reqlength)
            GROUP BY  subreq.reqlength,
                      subreq.reqpunch
          ) subItemR,
          (
            SELECT  subreq.reqlength,
                    subreq.reqpunch,
                    SUM(subasg.qty_asg_black + subasg.qty_asg_galv) totQty
            FROM  reco_rstx_cutreqv2 subreq, reco_rstx_cutasgv2 subasg
            WHERE   subreq.cutreq_id = subasg.cutreq_id
            AND     subreq.reqdate <= vd_LastDateOfRareLens
            AND     subreq.reqtype = pi_CurrentPartType
            AND     subreq.reqlength >= pi_MinimumPceSize
            AND     subreq.reqlength <= pi_MaximumPceSize
            AND     EXISTS (SELECT 1 FROM reco_rstx_rarelength rarelen
                            WHERE rarelen.unit_volume = subreq.reqlength)
            GROUP BY  subreq.reqlength,
                      subreq.reqpunch
          ) subItemA
          WHERE subItemR.reqlength = subItemA.reqlength (+)
          AND subItemR.reqpunch = subItemA.reqpunch (+)
        ) rareReqSubQ
    WHERE rareItemsSubQ.thelength = rareReqSubQ.reqlength (+)
    AND   rareItemsSubQ.thepunch = rareReqSubQ.reqpunch (+);
    
    -----
    -- Get pocket capacities
    
    SELECT daypocket.storage_capacity
    BULK COLLECT INTO oThePktCapacities
    FROM  reco_rstx_calday calday, reco_rstx_day_pocket daypocket
    WHERE daypocket.calday_id = calday.calday_id
    AND calday.thedate = pi_CurrentCutDate
    AND daypocket.parttype = pi_CurrentPartType
    AND NOT EXISTS (SELECT 1 FROM reco_rstx_day_pkt_bin subBins
                    WHERE subBins.day_pocket_id = daypocket.day_pocket_id);
    
    ----
    -- Grab a rare length and fill it
    
    DECLARE
      vn_SelectNumBars number;
      vn_PocketSize number;
      vn_TmpQtyPcs number;
      vn_TmpLen1 reco_rstx_cutreqv2.reqlength%TYPE;
      vc_TmpPun1 reco_rstx_cutreqv2.reqpunch%TYPE;
      vn_TmpLen2 reco_rstx_cutreqv2.reqlength%TYPE;
      vc_TmpPun2 reco_rstx_cutreqv2.reqpunch%TYPE;
      vn_TmpLen3 reco_rstx_cutreqv2.reqlength%TYPE;
      vc_TmpPun3 reco_rstx_cutreqv2.reqpunch%TYPE;
      vn_TmpLen4 reco_rstx_cutreqv2.reqlength%TYPE;
      vc_TmpPun4 reco_rstx_cutreqv2.reqpunch%TYPE;
    BEGIN
      FOR rarelenctr IN 1 .. oTheRareLenReqs.count -- loop for each rare length
      LOOP
        IF oTheRareLenReqs(rarelenctr).theqtyreq = 0
        THEN CONTINUE;
        END IF;
        
        vn_SelectNumBars := NULL;
        vn_PocketSize := NULL;
        vn_TmpQtyPcs := NULL;
        
        ---
        -- The punch for any parts / punch optimization is not
        -- as important for rare lengths (since they are special)
        -- So we just default the cut matrix to 'S' and
        -- only include special punch if it's required by the rarelen
        ---
        
        vc_TmpPun1 := 'S';
        vc_TmpPun2 := 'S';
        vc_TmpPun3 := 'S';
        vc_TmpPun4 := 'S';
        
        ---
        -- Select a quick-and-dirty pocket size
        ---
        
        FOR pktctr IN 1 .. oThePktCapacities.count
        LOOP
          IF oThePktCapacities(pktctr) >= oTheRareLenReqs(rarelenctr).theqtyreq
          AND ( vn_PocketSize IS NULL
                OR
                oThePktCapacities(pktctr) < vn_PocketSize)
          THEN
            vn_PocketSize := oThePktCapacities(pktctr);
            vn_TmpQtyPcs := 1;
          END IF;
        END LOOP;
        
        --if vn_PocketSize is null -- APR2013: 4/5 PIECE CODE TO UNCOMMENT
        --and oTheRareLenReqs(rarelenctr).thelength <= 19
        --then
        --  for pktctr in 1 .. oThePktCapacities.count
        --  loop
        --    if oThePktCapacities(pktctr)
        --          >= (ceil(oTheRareLenReqs(rarelenctr).theqtyreq / 2))
        --    and ( vn_PocketSize is null
        --          or
        --          oThePktCapacities(pktctr) < vn_PocketSize)
        --    then
        --      vn_PocketSize := oThePktCapacities(pktctr);
        --      vn_TmpQtyPcs := 2;
        --    end if;
        --  end loop;
        --end if; -- APR2013: 4/5 PIECE CODE TO UNCOMMENT
        --
        --if vn_PocketSize is null -- APR2013: 4/5 PIECE CODE TO UNCOMMENT
        --then
        --  for pktctr in 1 .. oThePktCapacities.count
        --  loop
        --    if vn_PocketSize is null
        --    or vn_PocketSize < oThePktCapacities(pktctr)
        --    then vn_PocketSize := oThePktCapacities(pktctr);
        --    end if;
        --  end loop;
        --  
        --  vn_TmpQtyPcs := 1;
        --  if oTheRareLenReqs(rarelenctr).thelength <= 19
        --  then vn_TmpQtyPcs := 2;
        --  end if;
        --end if; -- APR2013: 4/5 PIECE CODE TO UNCOMMENT
        
        IF vn_PocketSize IS NULL -- APR2013: 4/5 PIECE CODE TO REMOVE
        AND oTheRareLenReqs(rarelenctr).thelength <= 19
        AND oTheRareLenReqs(rarelenctr).thelength >= 10
        THEN
          FOR pktctr IN 1 .. oThePktCapacities.count
          LOOP
            IF oThePktCapacities(pktctr)
                  >= (CEIL(oTheRareLenReqs(rarelenctr).theqtyreq / 2))
            AND ( vn_PocketSize IS NULL
                  OR
                  oThePktCapacities(pktctr) < vn_PocketSize)
            THEN
              vn_PocketSize := oThePktCapacities(pktctr);
              vn_TmpQtyPcs := 2;
            END IF;
          END LOOP;
        END IF; -- APR2013: 4/5 PIECE CODE TO REMOVE
        
        IF vn_PocketSize IS NULL -- APR2013: 4/5 PIECE CODE TO REMOVE
        THEN
          FOR pktctr IN 1 .. oThePktCapacities.count
          LOOP
            IF vn_PocketSize IS NULL
            OR vn_PocketSize < oThePktCapacities(pktctr)
            THEN vn_PocketSize := oThePktCapacities(pktctr);
            END IF;
          END LOOP;
          
          vn_TmpQtyPcs := 1;
        END IF; -- APR2013: 4/5 PIECE CODE TO REMOVE
        
        ---
        -- Select a quick-and-dirty number of runs for the pocket
        ---
        
        vn_SelectNumBars := vn_PocketSize;
        
        LOOP
          IF vn_SelectNumBars - vn_QtyBarsPerRun
              >= CEIL(oTheRareLenReqs(rarelenctr).theqtyreq / vn_TmpQtyPcs)
          THEN
            vn_SelectNumBars := vn_SelectNumBars - vn_QtyBarsPerRun;
            CONTINUE;
          END IF;
          
          exit;
        END LOOP;
        
        DECLARE
          vb_AdjustedForDayMax BOOLEAN;
        BEGIN
          vb_AdjustedForDayMax := FALSE;
          
          LOOP
            IF vn_SelectNumBars + vn_CurrentBarQtyInDate > vn_MaxBars
            THEN
              vb_AdjustedForDayMax := TRUE;
              vn_SelectNumBars := vn_SelectNumBars - vn_QtyBarsPerRun;
              CONTINUE;
            END IF;
            
            exit;
          END LOOP;
          
          IF vb_AdjustedForDayMax = TRUE
          THEN
            vn_PocketSize := NULL;
            
            FOR pktctr IN 1 .. oThePktCapacities.count
            LOOP
              IF oThePktCapacities(pktctr) >= vn_SelectNumBars
              AND ( vn_PocketSize IS NULL
                    OR
                    vn_PocketSize > oThePktCapacities(pktctr))
              THEN vn_PocketSize := oThePktCapacities(pktctr);
              END IF;
            END LOOP;
          END IF;
        END;
        
        IF vn_TmpQtyPcs = 1
        THEN
          vn_TmpLen1 := oTheRareLenReqs(rarelenctr).thelength;
          vc_TmpPun1 := oTheRareLenReqs(rarelenctr).thepunch;
          
          IF oTheRareLenReqs(rarelenctr).thelength <= 23
          THEN
            vn_TmpLen2 :=
              FLOOR(
                (pi_GivenRawBarSize - oTheRareLenReqs(rarelenctr).thelength)
                                    / 2);
            vn_TmpLen3 :=
              CEIL(
                (pi_GivenRawBarSize - oTheRareLenReqs(rarelenctr).thelength)
                                    / 2);
            vn_TmpLen4 := 0;
            
            vn_TmpQtyPcs := 3;
            
            IF MOD(vn_TmpLen2,2) = 1 AND MOD(vn_TmpLen3,2) = 1
            THEN vn_TmpLen2 := vn_TmpLen2 + 1; vn_TmpLen3 := vn_TmpLen3 - 1;
            END IF;
          ELSIF oTheRareLenReqs(rarelenctr).thelength > 23
          THEN
            vn_TmpLen2 :=
              pi_GivenRawBarSize - oTheRareLenReqs(rarelenctr).thelength;
            vn_TmpLen3 := 0;
            vn_TmpLen4 := 0;
            
            vn_TmpQtyPcs := 2;
          END IF;
        ELSIF vn_TmpQtyPcs = 2
        THEN
          vn_TmpLen1 := oTheRareLenReqs(rarelenctr).thelength;
          vc_TmpPun1 := oTheRareLenReqs(rarelenctr).thepunch;
          vn_TmpLen2 := oTheRareLenReqs(rarelenctr).thelength;
          vc_TmpPun2 := oTheRareLenReqs(rarelenctr).thepunch;
          --if oTheRareLenReqs(rarelenctr).thelength <= 11
          --then -- APR2013: 4/5 PIECE CODE TO UNCOMMENT
          --  vn_TmpLen3 := -- APR2013: 4/5 PIECE CODE TO UNCOMMENT
          --    floor( (pi_GivenRawBarSize
          --                - (oTheRareLenReqs(rarelenctr).thelength * 2))
          --                          / 2);
          --  vn_TmpLen4 := -- APR2013: 4/5 PIECE CODE TO UNCOMMENT
          --    ceil( (pi_GivenRawBarSize
          --                - (oTheRareLenReqs(rarelenctr).thelength * 2))
          --                          / 2);
          --  
          --  vn_TmpQtyPcs := 4; -- APR2013: 4/5 PIECE CODE TO UNCOMMENT
          --  
          --  if mod(vn_TmpLen3,2) = 1 and mod(vn_TmpLen4,2) = 1
          --  then vn_TmpLen3 := vn_TmpLen3 + 1; vn_TmpLen4 := vn_TmpLen4 - 1;
          --  end if; -- APR2013: 4/5 PIECE CODE TO UNCOMMENT
          --elsif oTheRareLenReqs(rarelenctr).thelength > 11
          --then -- APR2013: 4/5 PIECE CODE TO UNCOMMENT
            vn_TmpLen3 := pi_GivenRawBarSize
                            - (oTheRareLenReqs(rarelenctr).thelength * 2);
            vn_TmpLen4 := 0;
            
            vn_TmpQtyPcs := 3;
          --end if; -- APR2013: 4/5 PIECE CODE TO UNCOMMENT
        END IF;
        
        apply_matrix_to_reqs(
          pi_CurrentPartType,
          pi_CurrentCutDate,
          vn_SelectNumBars,
          vn_PocketSize,
          vn_TmpQtyPcs,
          vn_TmpLen1,vc_TmpPun1,
          vn_TmpLen2,vc_TmpPun2,
          vn_TmpLen3,vc_TmpPun3,
          vn_TmpLen4,vc_TmpPun4);
        
        exit;
      END LOOP; -- loop for each rare length
    END;
    
  END LOOP; -- loop while empty pockets exist for us to use
  
  RETURN vc_OutputMessage;
END; -- fill_rarelen_reqs

--------------------------------------------------------------------------------
-- assign_runs_for_daypart
-- 
-- These items are given: CutDate/PartType/PocketsAvailable.
-- 
-- We grab each empty pocket available on the date,
-- and then assign some cut matrix to each of those pockets
-- 
-- PRE-CONDITIONS
-- : All-bins available for CutDate and PartType
-- : It's assumed that each pocket can at fit an entire 48'-bar of cuts
--   (e.g. We cut 16-12-10-10, so each pocket should
--         be AT LEAST size 56' (which is 16+2+12+2+10+2+10+2) )
-- : pi_BusinessDaysAhead must be >=0 and <= 10
-- : pi_CurrentCutDate should realistically be a working day in
--   the reco_rstx_calday table (have is_production_allowed set to Y)
-- : pi_MinimumPceSize and pi_MaximumPceSize correlate to the requirements
--   sizes in reco_rstx_cutreqv2 table
-- : This method ignores rare lengths <<
-- : This method ignores special lengths <<
--   If the caller wants to meet rare-length requirements,
--   then the caller should reference fill_rarelen_reqs before this method
-- : fill_rarelen_reqs should have been called before this
--   -- CONTINUE HERE This is a bug, this loop will infinite-loop
--   if there the only requirements left for givenDate are rare lengths !!
-- 
-- POST-CONDITIONS
-- : Populate these tables:
--   - reco_rstx_cutrun
--   - reco_rstx_cutasgv2
--   - reco_rstx_cutovg
--   - reco_rstx_day_pkt_bin
--   - reco_rstx_run_placement
--   (via the apply_matrix_to_reqs method)
-- : This method uses a loop to call apply_matrix_to_reqs many times.
--   The goal is to apply lots of cutmtx/quantity to fill the current date.
--   The loop stops when:
--   : No more empty Pockets are available for the given CutDate/PartType
--   -or-
--   : There are no Requirements left
--   -or-
--   : We have reached the MaxBarsPerDay
-- : returns 'DONE' when successful, or an error message when problems occur
FUNCTION assign_runs_for_daypart( pi_GivenRawBarSize IN number,
                                  pi_CurrentPartType IN varchar2,
                                  pi_CurrentCutDate IN date,
                                  pi_MinimumPceSize IN number,
                                  pi_MaximumPceSize IN number,
                                  pi_BusinessDaysAhead IN number)
RETURN varchar2
IS
  vd_BizDayMinus3 date;
  vd_BizDayMinus2 date;
  vd_BizDayMinus1 date;
  --vd_BizDayToday date; -- this is equal to pi_CurrentCutDate
  vd_BizDayTomorrow date;
  vd_BizDay2 date;
  vd_BizDay3 date;
  vd_BizDay4 date;
  vd_BizDay5 date;
  vd_BizDay6 date;
  vd_BizDay7 date;
  vd_BizDay8 date;
  vd_BizDay9 date;
  vd_BizDay10 date;
  vd_FirstFutureDay date;
  
  vn_MinPocketCapacity number;
  vn_MaxPocketCapacity number;
  
  vn_MaxBars number;
  vn_QtyBarsPerRun number;
  
  vn_CurrentBarQtyInDate number;
  
  vc_OutputMessage varchar2(1000);
  
BEGIN -- assign_runs_for_daypart
  
  -----
  -- Default output to an error
  -- (Unless the process exits at specific places, then we have an error)
  vc_OutputMessage := 'Error: Unkn assign error in assign_runs. Contact MIS';
  
  -----
  -- Preliminary business-day info
  
  vd_BizDayMinus3 := NULL;
  vd_BizDayMinus2 := NULL;
  vd_BizDayMinus1 := NULL;
  vd_BizDayTomorrow := NULL;
  vd_BizDay2 := NULL;
  vd_BizDay3 := NULL;
  vd_BizDay4 := NULL;
  vd_BizDay5 := NULL;
  vd_BizDay6 := NULL;
  vd_BizDay7 := NULL;
  vd_BizDay8 := NULL;
  vd_BizDay9 := NULL;
  vd_BizDay10 := NULL;
  vd_FirstFutureDay := NULL;
  
  FOR rec_pastbizday IN
    (
      SELECT ROWNUM therownum, thedate
      FROM
      (
        SELECT calday.thedate
        FROM reco_rstx_calday calday
        WHERE calday.thedate < pi_CurrentCutDate
        AND calday.is_production_allowed = 'Y'
        ORDER BY calday.thedate desc
      )
    )
  LOOP
    IF vd_BizDayMinus1 IS NOT NULL
    AND vd_BizDayMinus2 IS NOT NULL
    AND vd_BizDayMinus3 IS NOT NULL
    THEN exit;
    END IF;
    
    IF rec_pastbizday.therownum = 1
    THEN vd_BizDayMinus1 := rec_pastbizday.thedate;
    ELSIF rec_pastbizday.therownum = 2
    THEN vd_BizDayMinus2 := rec_pastbizday.thedate;
    ELSIF rec_pastbizday.therownum = 3
    THEN vd_BizDayMinus3 := rec_pastbizday.thedate;
    END IF;
  END LOOP;
  
  FOR rec_futurebizday IN
    (
      SELECT ROWNUM therownum, thedate
      FROM
      (
        SELECT calday.thedate
        FROM reco_rstx_calday calday
        WHERE calday.thedate > pi_CurrentCutDate
        AND calday.is_production_allowed = 'Y'
        ORDER BY calday.thedate
      )
    )
  LOOP
    IF rec_futurebizday.therownum > pi_BusinessDaysAhead
    OR rec_futurebizday.therownum > 10
    THEN
      vd_FirstFutureDay := rec_futurebizday.thedate;
      exit;
    END IF;
    
    IF rec_futurebizday.therownum = 1
    THEN vd_BizDayTomorrow := rec_futurebizday.thedate;
    ELSIF rec_futurebizday.therownum = 2
    THEN vd_BizDay2 := rec_futurebizday.thedate;
    ELSIF rec_futurebizday.therownum = 3
    THEN vd_BizDay3 := rec_futurebizday.thedate;
    ELSIF rec_futurebizday.therownum = 4
    THEN vd_BizDay4 := rec_futurebizday.thedate;
    ELSIF rec_futurebizday.therownum = 5
    THEN vd_BizDay5 := rec_futurebizday.thedate;
    ELSIF rec_futurebizday.therownum = 6
    THEN vd_BizDay6 := rec_futurebizday.thedate;
    ELSIF rec_futurebizday.therownum = 7
    THEN vd_BizDay7 := rec_futurebizday.thedate;
    ELSIF rec_futurebizday.therownum = 8
    THEN vd_BizDay8 := rec_futurebizday.thedate;
    ELSIF rec_futurebizday.therownum = 9
    THEN vd_BizDay9 := rec_futurebizday.thedate;
    ELSIF rec_futurebizday.therownum = 10
    THEN vd_BizDay10 := rec_futurebizday.thedate;
    END IF;
  END LOOP;
  
  -----
  -- We are about to start a loop
  -- LOOP
  --   If NoPocketsAvailableInGivenDate/GivenPartType
  --   or NoMoreRequirements
  --   or MaxBarsPerDayIsReached
  --   then exitOK;
  --   end If;
  --   
  --   Fill a pocket with cut parts
  -- END LOOP
  
  -- This loop is over 2,200 lines long !!
  
  -----
  -- Loop to apply_matrix_to_reqs many times
  
  LOOP -- Loop to apply_matrix_to_reqs many times
    
    -----
    -- Validate: Are there any requirements left?
    -- 
    -- If NO, then exit;
    
    -- Remember, we only consider requirements for current parameters:
    -- :pi_CurrentPartType
    -- :pi_MinimumPceSize
    -- :pi_MaximumPceSize
    
    DECLARE
      vc_Temp number;
    BEGIN
      SELECT 1 INTO vc_Temp
      FROM
            (
              SELECT  SUM(cutreq.qty_req_black + cutreq.qty_req_galv) totQty
              FROM  reco_rstx_cutreqv2 cutreq
              WHERE   cutreq.reqtype = pi_CurrentPartType
              AND     NOT EXISTS (SELECT 1 FROM reco_rstx_rarelength rarelen
                                  WHERE rarelen.unit_volume = cutreq.reqlength)
            ) subQReq,
            (
              SELECT  SUM(cutasg.qty_asg_black + cutasg.qty_asg_galv) totQty
              FROM  reco_rstx_cutreqv2 cutreq, reco_rstx_cutasgv2 cutasg
              WHERE   cutreq.cutreq_id = cutasg.cutreq_id
              AND     cutreq.reqtype = pi_CurrentPartType
              AND     NOT EXISTS (SELECT 1 FROM reco_rstx_rarelength rarelen
                                  WHERE rarelen.unit_volume = cutreq.reqlength)
            ) subQAsg
      WHERE subQReq.totQty > NVL(subQAsg.totQty,0);
    EXCEPTION
      WHEN NO_DATA_FOUND
      THEN
        vc_OutputMessage := 'DONE';
        exit;
      WHEN TOO_MANY_ROWS
      THEN
        NULL;
      WHEN others
      THEN
        vc_OutputMessage := 'Intenal Error at requirements review';
        exit;
    END;
    
    -----
    -- Validate that there are available pockets for the date/parttype,
    -- and access available pocket info for this date/parttype
    
    DECLARE
      vn_TmpQueryId number;
    BEGIN
      SELECT  calday.calday_id,
              calday.qty_bars_max,
              calday.qty_bars_per_run,
              MIN(daypocket.storage_capacity) minpktsize,
              MAX(daypocket.storage_capacity) maxpktsize
      INTO  vn_TmpQueryId,
            vn_MaxBars,
            vn_QtyBarsPerRun,
            vn_MinPocketCapacity,
            vn_MaxPocketCapacity
      FROM  reco_rstx_day_pocket daypocket,
            reco_rstx_calday calday
      WHERE   daypocket.calday_id = calday.calday_id
      AND     calday.thedate = pi_CurrentCutDate
      AND     daypocket.parttype = pi_CurrentPartType
      AND     NOT EXISTS (
                      SELECT 1
                      FROM reco_rstx_day_pkt_bin subBins
                      WHERE subBins.day_pocket_id = daypocket.day_pocket_id)
      GROUP BY calday.calday_id,calday.qty_bars_max,calday.qty_bars_per_run;
    EXCEPTION
      WHEN NO_DATA_FOUND
      THEN
        vc_OutputMessage := 'DONE';
        exit;
      WHEN others
      THEN
        vc_OutputMessage := 'Intenal Error at pockets review';
        exit;
    END;
    
    -----
    -- If we have reached our daily limit, then of course we are done,
    -- regardless of how many pockets were filled
    
    SELECT SUM(qty_bars_processed) INTO vn_CurrentBarQtyInDate
    FROM  (
            SELECT DISTINCT cutrun.run_number, cutrun.qty_bars_processed
            FROM  reco_rstx_calday calday,
                  reco_rstx_day_pocket daypocket,
                  reco_rstx_day_pkt_bin daypktbin,
                  reco_rstx_run_placement placement,
                  reco_rstx_cutrun cutrun
            WHERE   calday.thedate = pi_CurrentCutDate
            AND     calday.calday_id = daypocket.calday_id
            AND     daypocket.day_pocket_id = daypktbin.day_pocket_id
            AND     daypktbin.day_pkt_bin_id = placement.day_pkt_bin_id
            AND     placement.cutrun_id = cutrun.cutrun_id
          );
    
    IF vn_CurrentBarQtyInDate IS NULL
    THEN vn_CurrentBarQtyInDate := 0;
    END IF;
    
    IF vn_CurrentBarQtyInDate >= vn_MaxBars
    THEN
      vc_OutputMessage := 'DONE';
      IF vn_CurrentBarQtyInDate > vn_MaxBars
      THEN vc_OutputMessage := 'Internal Error 2030 - Excessive cutting in day';
      END IF;
      
      exit;
    END IF;
    
    -----
    -- Clear the combination tables
    
    DELETE FROM reco_rstx_sortedcut;
    DELETE FROM reco_rstx_cutcalc_daily;
    DELETE FROM reco_rstx_cutcalc_future;
    
    -----
    -- Set possible cuts into reco_rstx_sortedcut
    
    DECLARE
      vn_NewPc1Len number;
      vn_NewPc2Len number;
      vn_NewPc3Len number;
      vn_NewPc4Len number;
      
      vn_Other5 number;
    BEGIN
      FOR rec_cutmtx IN
        (
          SELECT  cutmtx.qty_pieces_made theqtypcs,
                  cutpce1.unit_volume thepce1,
                  NVL(cutpce2.unit_volume,0) thepce2,
                  NVL(cutpce3.unit_volume,0) thepce3,
                  NVL(cutpce4.unit_volume,0) thepce4
          FROM  reco_rstx_cutmtx cutmtx,
                reco_rstx_cutpce cutpce1,
                reco_rstx_cutpce cutpce2,
                reco_rstx_cutpce cutpce3,
                reco_rstx_cutpce cutpce4
          WHERE   cutmtx.ptype = pi_CurrentPartType
          AND     cutmtx.cutmtx_id = cutpce1.cutmtx_id
          AND     cutpce1.piece_number = 1
          AND NOT EXISTS (SELECT 1 FROM reco_rstx_rarelength subb
                          WHERE subb.unit_volume = NVL(cutpce1.unit_volume,0))
          AND     cutmtx.cutmtx_id = cutpce2.cutmtx_id (+)
          AND     cutpce2.piece_number (+) = 2
          AND NOT EXISTS (SELECT 1 FROM reco_rstx_rarelength subb
                          WHERE subb.unit_volume = NVL(cutpce2.unit_volume,0))
          AND     cutmtx.cutmtx_id = cutpce3.cutmtx_id (+)
          AND     cutpce3.piece_number (+) = 3
          AND NOT EXISTS (SELECT 1 FROM reco_rstx_rarelength subb
                          WHERE subb.unit_volume = NVL(cutpce3.unit_volume,0))
          AND     cutmtx.cutmtx_id = cutpce4.cutmtx_id (+)
          AND     cutpce4.piece_number (+) = 4
          AND NOT EXISTS (SELECT 1 FROM reco_rstx_rarelength subb
                          WHERE subb.unit_volume = NVL(cutpce4.unit_volume,0))
          AND (pi_GivenRawBarSize =
                  NVL(cutpce1.unit_volume,0) +
                  NVL(cutpce2.unit_volume,0) +
                  NVL(cutpce3.unit_volume,0) +
                  NVL(cutpce4.unit_volume,0))
        )
      LOOP
        SortMatrixPieces(rec_cutmtx.theqtypcs,
          rec_cutmtx.thepce1,rec_cutmtx.thepce2,
          rec_cutmtx.thepce3,rec_cutmtx.thepce4,NULL,
          FALSE,TRUE,
          vn_NewPc1Len,vn_NewPc2Len,vn_NewPc3Len,vn_NewPc4Len,vn_Other5);
        
        INSERT INTO reco_rstx_sortedcut (qtypcs,pc1len,pc2len,pc3len,pc4len)
        VALUES (rec_cutmtx.theqtypcs,vn_NewPc1Len,
                  NVL(vn_NewPc2Len,0),NVL(vn_NewPc3Len,0),NVL(vn_NewPc4Len,0));
      END LOOP;
    END;
    
    -----
    -- Summarize requirement information per-length per-day
    -- into the reco_rstx_cutcalc_daily table
    -- 
    -- This focus is on "day-by-day" processing, when things are urgent.
    -- So each-single-day for each-single-length will have requirement info
    -- 
    -- This does not look at "future" information.
    -- The "Future" part is done later
    
    INSERT INTO reco_rstx_cutcalc_daily
      (thelength,thepunch,
        qty_req_dayminus3,
        qty_req_dayminus2,
        qty_req_dayminus1,
        qty_req_today,
        qty_req_tomorrow,qty_req_day2,
        qty_req_day3,qty_req_day4,
        qty_req_day5,qty_req_day6,
        qty_req_day7,qty_req_day8,
        qty_req_day9,qty_req_day10)
    SELECT
      allItemsSubQ.thelength,
      allItemsSubQ.thepunch,
      NVL(bizdayminus3SubQ.qtyRemain,0),
      NVL(bizdayminus2SubQ.qtyRemain,0),
      NVL(bizdayminus1SubQ.qtyRemain,0),
      NVL(todaySubQ.qtyRemain,0),
      NVL(bizday1SubQ.qtyRemain,0),
      NVL(bizday2SubQ.qtyRemain,0),
      NVL(bizday3SubQ.qtyRemain,0),
      NVL(bizday4SubQ.qtyRemain,0),
      NVL(bizday5SubQ.qtyRemain,0),
      NVL(bizday6SubQ.qtyRemain,0),
      NVL(bizday7SubQ.qtyRemain,0),
      NVL(bizday8SubQ.qtyRemain,0),
      NVL(bizday9SubQ.qtyRemain,0),
      NVL(bizday10SubQ.qtyRemain,0)
    FROM
      (
        SELECT  lenpunmap.thelength thelength,
                lenpunmap.thepunch thepunch
        FROM reco_rstx_cutmtx_lenpunmap lenpunmap
        WHERE lenpunmap.thelength >= pi_MinimumPceSize
        AND lenpunmap.thelength <= pi_MaximumPceSize
        AND lenpunmap.thetype = pi_CurrentPartType
        AND NOT EXISTS (SELECT 1 FROM reco_rstx_rarelength rarelen
                        WHERE rarelen.unit_volume = lenpunmap.thelength)
      ) allItemsSubQ,
      (
        SELECT  subItemR.reqlength,
                subItemR.reqpunch,
                subItemR.totQty - NVL(subItemA.totQty,0) qtyRemain
        FROM
        (
          SELECT  subreq.reqlength,
                  subreq.reqpunch,
                  SUM(subreq.tot_qty_req) totQty
          FROM  reco_rstx_cutreqv2 subreq
          WHERE   subreq.reqdate <= vd_BizDayMinus3
          AND     subreq.reqtype = pi_CurrentPartType
          AND     subreq.reqlength >= pi_MinimumPceSize
          AND     subreq.reqlength <= pi_MaximumPceSize
          AND     NOT EXISTS (SELECT 1 FROM reco_rstx_rarelength rarelen
                              WHERE rarelen.unit_volume = subreq.reqlength)
          GROUP BY  subreq.reqlength,
                    subreq.reqpunch
        ) subItemR,
        (
          SELECT  subreq.reqlength,
                  subreq.reqpunch,
                  SUM(subasg.qty_asg_black + subasg.qty_asg_galv) totQty
          FROM  reco_rstx_cutreqv2 subreq, reco_rstx_cutasgv2 subasg
          WHERE   subreq.cutreq_id = subasg.cutreq_id
          AND     subreq.reqdate <= vd_BizDayMinus3
          AND     subreq.reqtype = pi_CurrentPartType
          AND     subreq.reqlength >= pi_MinimumPceSize
          AND     subreq.reqlength <= pi_MaximumPceSize
          AND     NOT EXISTS (SELECT 1 FROM reco_rstx_rarelength rarelen
                              WHERE rarelen.unit_volume = subreq.reqlength)
          GROUP BY  subreq.reqlength,
                    subreq.reqpunch
        ) subItemA
        WHERE subItemR.reqlength = subItemA.reqlength (+)
        AND   subItemR.reqpunch = subItemA.reqpunch (+)
      ) bizdayminus3SubQ,
      (
        SELECT  subItemR.reqlength,
                subItemR.reqpunch,
                subItemR.totQty - NVL(subItemA.totQty,0) qtyRemain
        FROM
        (
          SELECT  subreq.reqlength,
                  subreq.reqpunch,
                  SUM(subreq.tot_qty_req) totQty
          FROM  reco_rstx_cutreqv2 subreq
          WHERE   subreq.reqdate > vd_BizDayMinus3
          AND     subreq.reqdate <= vd_BizDayMinus2
          AND     subreq.reqtype = pi_CurrentPartType
          AND     subreq.reqlength >= pi_MinimumPceSize
          AND     subreq.reqlength <= pi_MaximumPceSize
          AND     NOT EXISTS (SELECT 1 FROM reco_rstx_rarelength rarelen
                              WHERE rarelen.unit_volume = subreq.reqlength)
          GROUP BY  subreq.reqlength,
                    subreq.reqpunch
        ) subItemR,
        (
          SELECT  subreq.reqlength,
                  subreq.reqpunch,
                  SUM(subasg.qty_asg_black + subasg.qty_asg_galv) totQty
          FROM  reco_rstx_cutreqv2 subreq, reco_rstx_cutasgv2 subasg
          WHERE   subreq.cutreq_id = subasg.cutreq_id
          AND     subreq.reqdate > vd_BizDayMinus3
          AND     subreq.reqdate <= vd_BizDayMinus2
          AND     subreq.reqtype = pi_CurrentPartType
          AND     subreq.reqlength >= pi_MinimumPceSize
          AND     subreq.reqlength <= pi_MaximumPceSize
          AND     NOT EXISTS (SELECT 1 FROM reco_rstx_rarelength rarelen
                              WHERE rarelen.unit_volume = subreq.reqlength)
          GROUP BY  subreq.reqlength,
                    subreq.reqpunch
        ) subItemA
        WHERE subItemR.reqlength = subItemA.reqlength (+)
        AND   subItemR.reqpunch = subItemA.reqpunch (+)
      ) bizdayminus2SubQ,
      (
        SELECT  subItemR.reqlength,
                subItemR.reqpunch,
                subItemR.totQty - NVL(subItemA.totQty,0) qtyRemain
        FROM
        (
          SELECT  subreq.reqlength,
                  subreq.reqpunch,
                  SUM(subreq.tot_qty_req) totQty
          FROM  reco_rstx_cutreqv2 subreq
          WHERE   subreq.reqdate > vd_BizDayMinus2
          AND     subreq.reqdate <= vd_BizDayMinus1
          AND     subreq.reqtype = pi_CurrentPartType
          AND     subreq.reqlength >= pi_MinimumPceSize
          AND     subreq.reqlength <= pi_MaximumPceSize
          AND     NOT EXISTS (SELECT 1 FROM reco_rstx_rarelength rarelen
                              WHERE rarelen.unit_volume = subreq.reqlength)
          GROUP BY  subreq.reqlength,
                    subreq.reqpunch
        ) subItemR,
        (
          SELECT  subreq.reqlength,
                  subreq.reqpunch,
                  SUM(subasg.qty_asg_black + subasg.qty_asg_galv) totQty
          FROM  reco_rstx_cutreqv2 subreq, reco_rstx_cutasgv2 subasg
          WHERE   subreq.cutreq_id = subasg.cutreq_id
          AND     subreq.reqdate > vd_BizDayMinus2
          AND     subreq.reqdate <= vd_BizDayMinus1
          AND     subreq.reqtype = pi_CurrentPartType
          AND     subreq.reqlength >= pi_MinimumPceSize
          AND     subreq.reqlength <= pi_MaximumPceSize
          AND     NOT EXISTS (SELECT 1 FROM reco_rstx_rarelength rarelen
                              WHERE rarelen.unit_volume = subreq.reqlength)
          GROUP BY  subreq.reqlength,
                    subreq.reqpunch
        ) subItemA
        WHERE subItemR.reqlength = subItemA.reqlength (+)
        AND   subItemR.reqpunch = subItemA.reqpunch (+)
      ) bizdayminus1SubQ,
      (
        SELECT  subItemR.reqlength,
                subItemR.reqpunch,
                subItemR.totQty - NVL(subItemA.totQty,0) qtyRemain
        FROM
        (
          SELECT  subreq.reqlength,
                  subreq.reqpunch,
                  SUM(subreq.tot_qty_req) totQty
          FROM  reco_rstx_cutreqv2 subreq
          WHERE   subreq.reqdate > vd_BizDayMinus1
          AND     subreq.reqdate <= pi_CurrentCutDate
          AND     subreq.reqtype = pi_CurrentPartType
          AND     subreq.reqlength >= pi_MinimumPceSize
          AND     subreq.reqlength <= pi_MaximumPceSize
          AND     NOT EXISTS (SELECT 1 FROM reco_rstx_rarelength rarelen
                              WHERE rarelen.unit_volume = subreq.reqlength)
          GROUP BY  subreq.reqlength,
                    subreq.reqpunch
        ) subItemR,
        (
          SELECT  subreq.reqlength,
                  subreq.reqpunch,
                  SUM(subasg.qty_asg_black + subasg.qty_asg_galv) totQty
          FROM  reco_rstx_cutreqv2 subreq, reco_rstx_cutasgv2 subasg
          WHERE   subreq.cutreq_id = subasg.cutreq_id
          AND     subreq.reqdate > vd_BizDayMinus1
          AND     subreq.reqdate <= pi_CurrentCutDate
          AND     subreq.reqtype = pi_CurrentPartType
          AND     subreq.reqlength >= pi_MinimumPceSize
          AND     subreq.reqlength <= pi_MaximumPceSize
          AND     NOT EXISTS (SELECT 1 FROM reco_rstx_rarelength rarelen
                              WHERE rarelen.unit_volume = subreq.reqlength)
          GROUP BY  subreq.reqlength,
                    subreq.reqpunch
        ) subItemA
        WHERE subItemR.reqlength = subItemA.reqlength (+)
        AND   subItemR.reqpunch = subItemA.reqpunch (+)
      ) todaySubQ,
      (
        SELECT  subItemR.reqlength,
                subItemR.reqpunch,
                subItemR.totQty - NVL(subItemA.totQty,0) qtyRemain
        FROM
        (
          SELECT  subreq.reqlength,
                  subreq.reqpunch,
                  SUM(subreq.tot_qty_req) totQty
          FROM  reco_rstx_cutreqv2 subreq
          WHERE   pi_BusinessDaysAhead >= 1
          AND     subreq.reqdate > pi_CurrentCutDate
          AND     subreq.reqdate <= vd_BizDayTomorrow
          AND     subreq.reqtype = pi_CurrentPartType
          AND     subreq.reqlength >= pi_MinimumPceSize
          AND     subreq.reqlength <= pi_MaximumPceSize
          AND     NOT EXISTS (SELECT 1 FROM reco_rstx_rarelength rarelen
                              WHERE rarelen.unit_volume = subreq.reqlength)
          GROUP BY  subreq.reqlength,
                    subreq.reqpunch
        ) subItemR,
        (
          SELECT  subreq.reqlength,
                  subreq.reqpunch,
                  SUM(subasg.qty_asg_black + subasg.qty_asg_galv) totQty
          FROM  reco_rstx_cutreqv2 subreq, reco_rstx_cutasgv2 subasg
          WHERE   pi_BusinessDaysAhead >= 1
          AND     subreq.cutreq_id = subasg.cutreq_id
          AND     subreq.reqdate > pi_CurrentCutDate
          AND     subreq.reqdate <= vd_BizDayTomorrow
          AND     subreq.reqtype = pi_CurrentPartType
          AND     subreq.reqlength >= pi_MinimumPceSize
          AND     subreq.reqlength <= pi_MaximumPceSize
          AND     NOT EXISTS (SELECT 1 FROM reco_rstx_rarelength rarelen
                              WHERE rarelen.unit_volume = subreq.reqlength)
          GROUP BY  subreq.reqlength,
                    subreq.reqpunch
        ) subItemA
        WHERE subItemR.reqlength = subItemA.reqlength (+)
        AND   subItemR.reqpunch = subItemA.reqpunch (+)
      ) bizday1SubQ,
      (
        SELECT  subItemR.reqlength,
                subItemR.reqpunch,
                subItemR.totQty - NVL(subItemA.totQty,0) qtyRemain
        FROM
        (
          SELECT  subreq.reqlength,
                  subreq.reqpunch,
                  SUM(subreq.tot_qty_req) totQty
          FROM  reco_rstx_cutreqv2 subreq
          WHERE   pi_BusinessDaysAhead >= 2
          AND     subreq.reqdate > vd_BizDayTomorrow
          AND     subreq.reqdate <= vd_BizDay2
          AND     subreq.reqtype = pi_CurrentPartType
          AND     subreq.reqlength >= pi_MinimumPceSize
          AND     subreq.reqlength <= pi_MaximumPceSize
          AND     NOT EXISTS (SELECT 1 FROM reco_rstx_rarelength rarelen
                              WHERE rarelen.unit_volume = subreq.reqlength)
          GROUP BY  subreq.reqlength,
                    subreq.reqpunch
        ) subItemR,
        (
          SELECT  subreq.reqlength,
                  subreq.reqpunch,
                  SUM(subasg.qty_asg_black + subasg.qty_asg_galv) totQty
          FROM  reco_rstx_cutreqv2 subreq, reco_rstx_cutasgv2 subasg
          WHERE   pi_BusinessDaysAhead >= 2
          AND     subreq.cutreq_id = subasg.cutreq_id
          AND     subreq.reqdate > vd_BizDayTomorrow
          AND     subreq.reqdate <= vd_BizDay2
          AND     subreq.reqtype = pi_CurrentPartType
          AND     subreq.reqlength >= pi_MinimumPceSize
          AND     subreq.reqlength <= pi_MaximumPceSize
          AND     NOT EXISTS (SELECT 1 FROM reco_rstx_rarelength rarelen
                              WHERE rarelen.unit_volume = subreq.reqlength)
          GROUP BY  subreq.reqlength,
                    subreq.reqpunch
        ) subItemA
        WHERE subItemR.reqlength = subItemA.reqlength (+)
        AND   subItemR.reqpunch = subItemA.reqpunch (+)
      ) bizday2SubQ,
      (
        SELECT  subItemR.reqlength,
                subItemR.reqpunch,
                subItemR.totQty - NVL(subItemA.totQty,0) qtyRemain
        FROM
        (
          SELECT  subreq.reqlength,
                  subreq.reqpunch,
                  SUM(subreq.tot_qty_req) totQty
          FROM  reco_rstx_cutreqv2 subreq
          WHERE   pi_BusinessDaysAhead >= 3
          AND     subreq.reqdate > vd_BizDay2
          AND     subreq.reqdate <= vd_BizDay3
          AND     subreq.reqtype = pi_CurrentPartType
          AND     subreq.reqlength >= pi_MinimumPceSize
          AND     subreq.reqlength <= pi_MaximumPceSize
          AND     NOT EXISTS (SELECT 1 FROM reco_rstx_rarelength rarelen
                              WHERE rarelen.unit_volume = subreq.reqlength)
          GROUP BY  subreq.reqlength,
                    subreq.reqpunch
        ) subItemR,
        (
          SELECT  subreq.reqlength,
                  subreq.reqpunch,
                  SUM(subasg.qty_asg_black + subasg.qty_asg_galv) totQty
          FROM  reco_rstx_cutreqv2 subreq, reco_rstx_cutasgv2 subasg
          WHERE   pi_BusinessDaysAhead >= 3
          AND     subreq.cutreq_id = subasg.cutreq_id
          AND     subreq.reqdate > vd_BizDay2
          AND     subreq.reqdate <= vd_BizDay3
          AND     subreq.reqtype = pi_CurrentPartType
          AND     subreq.reqlength >= pi_MinimumPceSize
          AND     subreq.reqlength <= pi_MaximumPceSize
          AND     NOT EXISTS (SELECT 1 FROM reco_rstx_rarelength rarelen
                              WHERE rarelen.unit_volume = subreq.reqlength)
          GROUP BY  subreq.reqlength,
                    subreq.reqpunch
        ) subItemA
        WHERE subItemR.reqlength = subItemA.reqlength (+)
        AND   subItemR.reqpunch = subItemA.reqpunch (+)
      ) bizday3SubQ,
      (
        SELECT  subItemR.reqlength,
                subItemR.reqpunch,
                subItemR.totQty - NVL(subItemA.totQty,0) qtyRemain
        FROM
        (
          SELECT  subreq.reqlength,
                  subreq.reqpunch,
                  SUM(subreq.tot_qty_req) totQty
          FROM  reco_rstx_cutreqv2 subreq
          WHERE   pi_BusinessDaysAhead >= 4
          AND     subreq.reqdate > vd_BizDay3
          AND     subreq.reqdate <= vd_BizDay4
          AND     subreq.reqtype = pi_CurrentPartType
          AND     subreq.reqlength >= pi_MinimumPceSize
          AND     subreq.reqlength <= pi_MaximumPceSize
          AND     NOT EXISTS (SELECT 1 FROM reco_rstx_rarelength rarelen
                              WHERE rarelen.unit_volume = subreq.reqlength)
          GROUP BY  subreq.reqlength,
                    subreq.reqpunch
        ) subItemR,
        (
          SELECT  subreq.reqlength,
                  subreq.reqpunch,
                  SUM(subasg.qty_asg_black + subasg.qty_asg_galv) totQty
          FROM  reco_rstx_cutreqv2 subreq, reco_rstx_cutasgv2 subasg
          WHERE   pi_BusinessDaysAhead >= 4
          AND     subreq.cutreq_id = subasg.cutreq_id
          AND     subreq.reqdate > vd_BizDay3
          AND     subreq.reqdate <= vd_BizDay4
          AND     subreq.reqtype = pi_CurrentPartType
          AND     subreq.reqlength >= pi_MinimumPceSize
          AND     subreq.reqlength <= pi_MaximumPceSize
          AND     NOT EXISTS (SELECT 1 FROM reco_rstx_rarelength rarelen
                              WHERE rarelen.unit_volume = subreq.reqlength)
          GROUP BY  subreq.reqlength,
                    subreq.reqpunch
        ) subItemA
        WHERE subItemR.reqlength = subItemA.reqlength (+)
        AND   subItemR.reqpunch = subItemA.reqpunch (+)
      ) bizday4SubQ,
      (
        SELECT  subItemR.reqlength,
                subItemR.reqpunch,
                subItemR.totQty - NVL(subItemA.totQty,0) qtyRemain
        FROM
        (
          SELECT  subreq.reqlength,
                  subreq.reqpunch,
                  SUM(subreq.tot_qty_req) totQty
          FROM  reco_rstx_cutreqv2 subreq
          WHERE   pi_BusinessDaysAhead >= 5
          AND     subreq.reqdate > vd_BizDay4
          AND     subreq.reqdate <= vd_BizDay5
          AND     subreq.reqtype = pi_CurrentPartType
          AND     subreq.reqlength >= pi_MinimumPceSize
          AND     subreq.reqlength <= pi_MaximumPceSize
          AND     NOT EXISTS (SELECT 1 FROM reco_rstx_rarelength rarelen
                              WHERE rarelen.unit_volume = subreq.reqlength)
          GROUP BY  subreq.reqlength,
                    subreq.reqpunch
        ) subItemR,
        (
          SELECT  subreq.reqlength,
                  subreq.reqpunch,
                  SUM(subasg.qty_asg_black + subasg.qty_asg_galv) totQty
          FROM  reco_rstx_cutreqv2 subreq, reco_rstx_cutasgv2 subasg
          WHERE   pi_BusinessDaysAhead >= 5
          AND     subreq.cutreq_id = subasg.cutreq_id
          AND     subreq.reqdate > vd_BizDay4
          AND     subreq.reqdate <= vd_BizDay5
          AND     subreq.reqtype = pi_CurrentPartType
          AND     subreq.reqlength >= pi_MinimumPceSize
          AND     subreq.reqlength <= pi_MaximumPceSize
          AND     NOT EXISTS (SELECT 1 FROM reco_rstx_rarelength rarelen
                              WHERE rarelen.unit_volume = subreq.reqlength)
          GROUP BY  subreq.reqlength,
                    subreq.reqpunch
        ) subItemA
        WHERE subItemR.reqlength = subItemA.reqlength (+)
        AND   subItemR.reqpunch = subItemA.reqpunch (+)
      ) bizday5SubQ,
      (
        SELECT  subItemR.reqlength,
                subItemR.reqpunch,
                subItemR.totQty - NVL(subItemA.totQty,0) qtyRemain
        FROM
        (
          SELECT  subreq.reqlength,
                  subreq.reqpunch,
                  SUM(subreq.tot_qty_req) totQty
          FROM  reco_rstx_cutreqv2 subreq
          WHERE   pi_BusinessDaysAhead >= 6
          AND     subreq.reqdate > vd_BizDay5
          AND     subreq.reqdate <= vd_BizDay6
          AND     subreq.reqtype = pi_CurrentPartType
          AND     subreq.reqlength >= pi_MinimumPceSize
          AND     subreq.reqlength <= pi_MaximumPceSize
          AND     NOT EXISTS (SELECT 1 FROM reco_rstx_rarelength rarelen
                              WHERE rarelen.unit_volume = subreq.reqlength)
          GROUP BY  subreq.reqlength,
                    subreq.reqpunch
        ) subItemR,
        (
          SELECT  subreq.reqlength,
                  subreq.reqpunch,
                  SUM(subasg.qty_asg_black + subasg.qty_asg_galv) totQty
          FROM  reco_rstx_cutreqv2 subreq, reco_rstx_cutasgv2 subasg
          WHERE   pi_BusinessDaysAhead >= 6
          AND     subreq.cutreq_id = subasg.cutreq_id
          AND     subreq.reqdate > vd_BizDay5
          AND     subreq.reqdate <= vd_BizDay6
          AND     subreq.reqtype = pi_CurrentPartType
          AND     subreq.reqlength >= pi_MinimumPceSize
          AND     subreq.reqlength <= pi_MaximumPceSize
          AND     NOT EXISTS (SELECT 1 FROM reco_rstx_rarelength rarelen
                              WHERE rarelen.unit_volume = subreq.reqlength)
          GROUP BY  subreq.reqlength,
                    subreq.reqpunch
        ) subItemA
        WHERE subItemR.reqlength = subItemA.reqlength (+)
        AND   subItemR.reqpunch = subItemA.reqpunch (+)
      ) bizday6SubQ,
      (
        SELECT  subItemR.reqlength,
                subItemR.reqpunch,
                subItemR.totQty - NVL(subItemA.totQty,0) qtyRemain
        FROM
        (
          SELECT  subreq.reqlength,
                  subreq.reqpunch, -- CONTINUE HERE remove Group by for Req?
                  SUM(subreq.tot_qty_req) totQty
          FROM  reco_rstx_cutreqv2 subreq
          WHERE   pi_BusinessDaysAhead >= 7
          AND     subreq.reqdate > vd_BizDay6
          AND     subreq.reqdate <= vd_BizDay7
          AND     subreq.reqtype = pi_CurrentPartType
          AND     subreq.reqlength >= pi_MinimumPceSize
          AND     subreq.reqlength <= pi_MaximumPceSize
          AND     NOT EXISTS (SELECT 1 FROM reco_rstx_rarelength rarelen
                              WHERE rarelen.unit_volume = subreq.reqlength)
          GROUP BY  subreq.reqlength,
                    subreq.reqpunch
        ) subItemR,
        (
          SELECT  subreq.reqlength,
                  subreq.reqpunch,
                  SUM(subasg.qty_asg_black + subasg.qty_asg_galv) totQty
          FROM  reco_rstx_cutreqv2 subreq, reco_rstx_cutasgv2 subasg
          WHERE   pi_BusinessDaysAhead >= 7
          AND     subreq.cutreq_id = subasg.cutreq_id
          AND     subreq.reqdate > vd_BizDay6
          AND     subreq.reqdate <= vd_BizDay7
          AND     subreq.reqtype = pi_CurrentPartType
          AND     subreq.reqlength >= pi_MinimumPceSize
          AND     subreq.reqlength <= pi_MaximumPceSize
          AND     NOT EXISTS (SELECT 1 FROM reco_rstx_rarelength rarelen
                              WHERE rarelen.unit_volume = subreq.reqlength)
          GROUP BY  subreq.reqlength,
                    subreq.reqpunch
        ) subItemA
        WHERE subItemR.reqlength = subItemA.reqlength (+)
        AND   subItemR.reqpunch = subItemA.reqpunch (+)
      ) bizday7SubQ,
      (
        SELECT  subItemR.reqlength,
                subItemR.reqpunch,
                subItemR.totQty - NVL(subItemA.totQty,0) qtyRemain
        FROM
        (
          SELECT  subreq.reqlength,
                  subreq.reqpunch, -- CONTINUE HERE remove Group by for Req?
                  SUM(subreq.tot_qty_req) totQty
          FROM  reco_rstx_cutreqv2 subreq
          WHERE   pi_BusinessDaysAhead >= 8
          AND     subreq.reqdate > vd_BizDay7
          AND     subreq.reqdate <= vd_BizDay8
          AND     subreq.reqtype = pi_CurrentPartType
          AND     subreq.reqlength >= pi_MinimumPceSize
          AND     subreq.reqlength <= pi_MaximumPceSize
          AND     NOT EXISTS (SELECT 1 FROM reco_rstx_rarelength rarelen
                              WHERE rarelen.unit_volume = subreq.reqlength)
          GROUP BY  subreq.reqlength,
                    subreq.reqpunch
        ) subItemR,
        (
          SELECT  subreq.reqlength,
                  subreq.reqpunch,
                  SUM(subasg.qty_asg_black + subasg.qty_asg_galv) totQty
          FROM  reco_rstx_cutreqv2 subreq, reco_rstx_cutasgv2 subasg
          WHERE   pi_BusinessDaysAhead >= 8
          AND     subreq.cutreq_id = subasg.cutreq_id
          AND     subreq.reqdate > vd_BizDay7
          AND     subreq.reqdate <= vd_BizDay8
          AND     subreq.reqtype = pi_CurrentPartType
          AND     subreq.reqlength >= pi_MinimumPceSize
          AND     subreq.reqlength <= pi_MaximumPceSize
          AND     NOT EXISTS (SELECT 1 FROM reco_rstx_rarelength rarelen
                              WHERE rarelen.unit_volume = subreq.reqlength)
          GROUP BY  subreq.reqlength,
                    subreq.reqpunch
        ) subItemA
        WHERE subItemR.reqlength = subItemA.reqlength (+)
        AND   subItemR.reqpunch = subItemA.reqpunch (+)
      ) bizday8SubQ,
      (
        SELECT  subItemR.reqlength,
                subItemR.reqpunch,
                subItemR.totQty - NVL(subItemA.totQty,0) qtyRemain
        FROM
        (
          SELECT  subreq.reqlength,
                  subreq.reqpunch, -- CONTINUE HERE remove Group by for Req?
                  SUM(subreq.tot_qty_req) totQty
          FROM  reco_rstx_cutreqv2 subreq
          WHERE   pi_BusinessDaysAhead >= 9
          AND     subreq.reqdate > vd_BizDay8
          AND     subreq.reqdate <= vd_BizDay9
          AND     subreq.reqtype = pi_CurrentPartType
          AND     subreq.reqlength >= pi_MinimumPceSize
          AND     subreq.reqlength <= pi_MaximumPceSize
          AND     NOT EXISTS (SELECT 1 FROM reco_rstx_rarelength rarelen
                              WHERE rarelen.unit_volume = subreq.reqlength)
          GROUP BY  subreq.reqlength,
                    subreq.reqpunch
        ) subItemR,
        (
          SELECT  subreq.reqlength,
                  subreq.reqpunch,
                  SUM(subasg.qty_asg_black + subasg.qty_asg_galv) totQty
          FROM  reco_rstx_cutreqv2 subreq, reco_rstx_cutasgv2 subasg
          WHERE   pi_BusinessDaysAhead >= 9
          AND     subreq.cutreq_id = subasg.cutreq_id
          AND     subreq.reqdate > vd_BizDay8
          AND     subreq.reqdate <= vd_BizDay9
          AND     subreq.reqtype = pi_CurrentPartType
          AND     subreq.reqlength >= pi_MinimumPceSize
          AND     subreq.reqlength <= pi_MaximumPceSize
          AND     NOT EXISTS (SELECT 1 FROM reco_rstx_rarelength rarelen
                              WHERE rarelen.unit_volume = subreq.reqlength)
          GROUP BY  subreq.reqlength,
                    subreq.reqpunch
        ) subItemA
        WHERE subItemR.reqlength = subItemA.reqlength (+)
        AND   subItemR.reqpunch = subItemA.reqpunch (+)
      ) bizday9SubQ,
      (
        SELECT  subItemR.reqlength,
                subItemR.reqpunch,
                subItemR.totQty - NVL(subItemA.totQty,0) qtyRemain
        FROM
        (
          SELECT  subreq.reqlength,
                  subreq.reqpunch, -- CONTINUE HERE remove Group by for Req?
                  SUM(subreq.tot_qty_req) totQty
          FROM  reco_rstx_cutreqv2 subreq
          WHERE   pi_BusinessDaysAhead >= 10
          AND     subreq.reqdate > vd_BizDay9
          AND     subreq.reqdate <= vd_BizDay10
          AND     subreq.reqtype = pi_CurrentPartType
          AND     subreq.reqlength >= pi_MinimumPceSize
          AND     subreq.reqlength <= pi_MaximumPceSize
          AND     NOT EXISTS (SELECT 1 FROM reco_rstx_rarelength rarelen
                              WHERE rarelen.unit_volume = subreq.reqlength)
          GROUP BY  subreq.reqlength,
                    subreq.reqpunch
        ) subItemR,
        (
          SELECT  subreq.reqlength,
                  subreq.reqpunch,
                  SUM(subasg.qty_asg_black + subasg.qty_asg_galv) totQty
          FROM  reco_rstx_cutreqv2 subreq, reco_rstx_cutasgv2 subasg
          WHERE   pi_BusinessDaysAhead >= 10
          AND     subreq.cutreq_id = subasg.cutreq_id
          AND     subreq.reqdate > vd_BizDay9
          AND     subreq.reqdate <= vd_BizDay10
          AND     subreq.reqtype = pi_CurrentPartType
          AND     subreq.reqlength >= pi_MinimumPceSize
          AND     subreq.reqlength <= pi_MaximumPceSize
          AND     NOT EXISTS (SELECT 1 FROM reco_rstx_rarelength rarelen
                              WHERE rarelen.unit_volume = subreq.reqlength)
          GROUP BY  subreq.reqlength,
                    subreq.reqpunch
        ) subItemA
        WHERE subItemR.reqlength = subItemA.reqlength (+)
        AND   subItemR.reqpunch = subItemA.reqpunch (+)
      ) bizday10SubQ
    WHERE allItemsSubQ.thelength = bizdayminus3SubQ.reqlength (+)
    AND allItemsSubQ.thepunch  = bizdayminus3SubQ.reqpunch (+)
    AND allItemsSubQ.thelength = bizdayminus2SubQ.reqlength (+)
    AND allItemsSubQ.thepunch  = bizdayminus2SubQ.reqpunch (+)
    AND allItemsSubQ.thelength = bizdayminus1SubQ.reqlength (+)
    AND allItemsSubQ.thepunch  = bizdayminus1SubQ.reqpunch (+)
    AND allItemsSubQ.thelength = todaySubQ.reqlength (+)
    AND allItemsSubQ.thepunch  = todaySubQ.reqpunch (+)
    AND allItemsSubQ.thelength = bizday1SubQ.reqlength (+)
    AND allItemsSubQ.thepunch  = bizday1SubQ.reqpunch (+)
    AND allItemsSubQ.thelength = bizday2SubQ.reqlength (+)
    AND allItemsSubQ.thepunch  = bizday2SubQ.reqpunch (+)
    AND allItemsSubQ.thelength = bizday3SubQ.reqlength (+)
    AND allItemsSubQ.thepunch  = bizday3SubQ.reqpunch (+)
    AND allItemsSubQ.thelength = bizday4SubQ.reqlength (+)
    AND allItemsSubQ.thepunch  = bizday4SubQ.reqpunch (+)
    AND allItemsSubQ.thelength = bizday5SubQ.reqlength (+)
    AND allItemsSubQ.thepunch  = bizday5SubQ.reqpunch (+)
    AND allItemsSubQ.thelength = bizday6SubQ.reqlength (+)
    AND allItemsSubQ.thepunch  = bizday6SubQ.reqpunch (+)
    AND allItemsSubQ.thelength = bizday7SubQ.reqlength (+)
    AND allItemsSubQ.thepunch  = bizday7SubQ.reqpunch (+)
    AND allItemsSubQ.thelength = bizday8SubQ.reqlength (+)
    AND allItemsSubQ.thepunch  = bizday8SubQ.reqpunch (+)
    AND allItemsSubQ.thelength = bizday9SubQ.reqlength (+)
    AND allItemsSubQ.thepunch  = bizday9SubQ.reqpunch (+)
    AND allItemsSubQ.thelength = bizday10SubQ.reqlength (+)
    AND allItemsSubQ.thepunch  = bizday10SubQ.reqpunch (+);
    
    -----
    -- Now, summarize requirement information per-length per-day
    -- into the reco_rstx_cutcalc_FUTURE table
    -- (any requirements that fall into "future" range)
    -- 
    -- We want to iterate through each
    -- futureday/requirement for a given length/punch.
    -- The information in reco_rstx_cutcalc_future reflects this
    
    INSERT INTO reco_rstx_cutcalc_future
      (thelength,thepunch,thedate,qty_remaining)
    SELECT
      subItemR.reqlength,
      subItemR.reqpunch,
      subItemR.reqdate,
      subItemR.tot_qty_req - NVL(subItemA.totQty,0) qtyRemain
    FROM
    (
      SELECT  subreq.cutreq_id,
              subreq.reqlength,
              subreq.reqpunch,
              subreq.reqdate,
              subreq.tot_qty_req
      FROM  reco_rstx_cutreqv2 subreq
      WHERE   subreq.reqdate >= vd_FirstFutureDay
      AND     subreq.reqtype = pi_CurrentPartType
      AND     subreq.reqlength >= pi_MinimumPceSize
      AND     subreq.reqlength <= pi_MaximumPceSize
      AND     NOT EXISTS (SELECT 1 FROM reco_rstx_rarelength rarelen
                          WHERE rarelen.unit_volume = subreq.reqlength)
    ) subItemR,
    (
      SELECT  subreq.cutreq_id,
              subreq.reqlength,
              subreq.reqpunch,
              subreq.reqdate,
              SUM(subasg.qty_asg_black + subasg.qty_asg_galv) totQty
      FROM  reco_rstx_cutreqv2 subreq, reco_rstx_cutasgv2 subasg
      WHERE   subreq.cutreq_id = subasg.cutreq_id
      AND     subreq.reqdate >= vd_FirstFutureDay
      AND     subreq.reqtype = pi_CurrentPartType
      AND     subreq.reqlength >= pi_MinimumPceSize
      AND     subreq.reqlength <= pi_MaximumPceSize
      AND     NOT EXISTS (SELECT 1 FROM reco_rstx_rarelength rarelen
                          WHERE rarelen.unit_volume = subreq.reqlength)
      GROUP BY  subreq.cutreq_id,
                subreq.reqlength,
                subreq.reqpunch,
                subreq.reqdate
    ) subItemA
    WHERE subItemR.cutreq_id = subItemA.cutreq_id (+);
    
    -----
    -- Select a good Pocket/Matrix/Qty for the
    -- given date and parttype
    -- 
    -- The goal of this code is to call apply_matrix_to_reqs
    
    DECLARE -- Large block of code
      
      TYPE rec_lenasg IS record ( qty_asg_dminus3 number,
                                  qty_asg_dminus2 number,
                                  qty_asg_dminus1 number,
                                  qty_asg_today number,
                                  qty_asg_tomorrow number,
                                  qty_asg_d2 number,
                                  qty_asg_d3 number,
                                  qty_asg_d4 number,
                                  qty_asg_d5 number,
                                  qty_asg_d6 number,
                                  qty_asg_d7 number,
                                  qty_asg_d8 number,
                                  qty_asg_d9 number,
                                  qty_asg_d10 number,
                                  qty_asg_future number,
                                  rating_asg_future number,
                                  qty_asg_overage number);
      
      vr_BlankLenAsg rec_lenasg;
      
      TYPE rec_Result IS record (
        qtypcs number,
        p1len reco_rstx_cutreqv2.reqlength%TYPE,
        p1pun reco_rstx_cutreqv2.reqpunch%TYPE,
        p1asgs rec_lenasg,
        p2len reco_rstx_cutreqv2.reqlength%TYPE,
        p2pun reco_rstx_cutreqv2.reqpunch%TYPE,
        p2asgs rec_lenasg,
        p3len reco_rstx_cutreqv2.reqlength%TYPE,
        p3pun reco_rstx_cutreqv2.reqpunch%TYPE,
        p3asgs rec_lenasg,
        p4len reco_rstx_cutreqv2.reqlength%TYPE,
        p4pun reco_rstx_cutreqv2.reqpunch%TYPE,
        p4asgs rec_lenasg,
        totals rec_lenasg);
      
      vr_BlankResult rec_Result;
      
      TYPE rec_ResultPerQty IS record ( thecapacity number,
                                        theresult rec_Result);
      
      TYPE coll_ResultPerQty IS TABLE OF rec_ResultPerQty;
      
      --oTheResPerQty coll_ResultPerQty; -- Fetched, so don't initialize
      oBestUse coll_ResultPerQty := coll_ResultPerQty();
                                        -- Initialize since not fetched
      
      ----------------------------------------------------------
      -- Compare two possible matrices / "results" and determine
      -- which one is better
      -- 
      -- To determine the best matrix, we look at how well
      -- the matrix is applied to the requirements
      -- 
      -- If we have requirements within the "business-days-ahead"
      -- range, then those are treated as urgent.
      -- e.g. If we want 3-days-ahead, and one matrix fills some
      --      requirements for "tomorrow", then that is the best
      --      matrix because if fills the most/current urgent
      --      requirements
      -- 
      -- For other "future" requirements, we compare results
      -- depending on:
      -- : How far ahead is the requirement?
      -- : How large is the requirement?
      -- : How much overage is made?
      -- The term "future" indicates requirements that are
      -- beyond the "business-days-ahead" range
      FUNCTION CurrentResultIsBetter (pi_Best IN rec_Result,
                                      pi_Curr IN rec_Result)
      RETURN BOOLEAN
      IS
      BEGIN -- CurrentResultIsBetter
        
        -- Do the easy check first:
        -- : Compare numbers based on urgent / business-days-ahead
        --   requirements
        -- Whichever matrix hits more urgent requirements wins
        
        IF pi_Curr.totals.qty_asg_dminus3 != pi_Best.totals.qty_asg_dminus3
        THEN
          IF pi_Curr.totals.qty_asg_dminus3 > pi_Best.totals.qty_asg_dminus3
          THEN RETURN TRUE;
          END IF;
          
          RETURN FALSE;
        END IF;
        
        IF pi_Curr.totals.qty_asg_dminus2 != pi_Best.totals.qty_asg_dminus2
        THEN
          IF pi_Curr.totals.qty_asg_dminus2 > pi_Best.totals.qty_asg_dminus2
          THEN RETURN TRUE;
          END IF;
          
          RETURN FALSE;
        END IF;
        
        IF pi_Curr.totals.qty_asg_dminus1 != pi_Best.totals.qty_asg_dminus1
        THEN
          IF pi_Curr.totals.qty_asg_dminus1 > pi_Best.totals.qty_asg_dminus1
          THEN RETURN TRUE;
          END IF;
          
          RETURN FALSE;
        END IF;
        
        IF pi_Curr.totals.qty_asg_today != pi_Best.totals.qty_asg_today
        THEN
          IF pi_Curr.totals.qty_asg_today > pi_Best.totals.qty_asg_today
          THEN RETURN TRUE;
          END IF;
          
          RETURN FALSE;
        END IF;
        
        IF pi_Curr.totals.qty_asg_tomorrow != pi_Best.totals.qty_asg_tomorrow
        THEN
          IF pi_Curr.totals.qty_asg_tomorrow > pi_Best.totals.qty_asg_tomorrow
          THEN RETURN TRUE;
          END IF;
          
          RETURN FALSE;
        END IF;
        
        IF pi_Curr.totals.qty_asg_d2 != pi_Best.totals.qty_asg_d2
        THEN
          IF pi_Curr.totals.qty_asg_d2 > pi_Best.totals.qty_asg_d2
          THEN RETURN TRUE;
          END IF;
          
          RETURN FALSE;
        END IF;
        
        IF pi_Curr.totals.qty_asg_d3 != pi_Best.totals.qty_asg_d3
        THEN
          IF pi_Curr.totals.qty_asg_d3 > pi_Best.totals.qty_asg_d3
          THEN RETURN TRUE;
          END IF;
          
          RETURN FALSE;
        END IF;
        
        IF pi_Curr.totals.qty_asg_d4 != pi_Best.totals.qty_asg_d4
        THEN
          IF pi_Curr.totals.qty_asg_d4 > pi_Best.totals.qty_asg_d4
          THEN RETURN TRUE;
          END IF;
          
          RETURN FALSE;
        END IF;
        
        IF pi_Curr.totals.qty_asg_d5 != pi_Best.totals.qty_asg_d5
        THEN
          IF pi_Curr.totals.qty_asg_d5 > pi_Best.totals.qty_asg_d5
          THEN RETURN TRUE;
          END IF;
          
          RETURN FALSE;
        END IF;
        
        IF pi_Curr.totals.qty_asg_d6 != pi_Best.totals.qty_asg_d6
        THEN
          IF pi_Curr.totals.qty_asg_d6 > pi_Best.totals.qty_asg_d6
          THEN RETURN TRUE;
          END IF;
          
          RETURN FALSE;
        END IF;
        
        IF pi_Curr.totals.qty_asg_d7 != pi_Best.totals.qty_asg_d7
        THEN
          IF pi_Curr.totals.qty_asg_d7 > pi_Best.totals.qty_asg_d7
          THEN RETURN TRUE;
          END IF;
          
          RETURN FALSE;
        END IF;
        
        IF pi_Curr.totals.qty_asg_d8 != pi_Best.totals.qty_asg_d8
        THEN
          IF pi_Curr.totals.qty_asg_d8 > pi_Best.totals.qty_asg_d8
          THEN RETURN TRUE;
          END IF;
          
          RETURN FALSE;
        END IF;
        
        IF pi_Curr.totals.qty_asg_d9 != pi_Best.totals.qty_asg_d9
        THEN
          IF pi_Curr.totals.qty_asg_d9 > pi_Best.totals.qty_asg_d9
          THEN RETURN TRUE;
          END IF;
          
          RETURN FALSE;
        END IF;
        
        IF pi_Curr.totals.qty_asg_d10 != pi_Best.totals.qty_asg_d10
        THEN
          IF pi_Curr.totals.qty_asg_d10 > pi_Best.totals.qty_asg_d10
          THEN RETURN TRUE;
          END IF;
          
          RETURN FALSE;
        END IF;
        
        -- If we get here, then we know that both of the
        -- best/current results fill the same urgent stuff.
        -- 
        -- So now we gotta judge future and overage comparisons
        
        IF pi_Curr.totals.rating_asg_future > pi_Best.totals.rating_asg_future
        THEN RETURN TRUE;
        ELSIF pi_Curr.totals.rating_asg_future = pi_Best.totals.rating_asg_future
        AND pi_Curr.totals.qty_asg_overage < pi_Best.totals.qty_asg_overage
        THEN RETURN TRUE;
        END IF;
        
        --declare
        --  vn_FutureQtyFudge number;
        --  vn_OverageFudge number;
        --begin
        --  vn_FutureQtyFudge := pi_Best.totals.qty_asg_future - 50;
        --  if vn_FutureQtyFudge < 1
        --  then vn_FutureQtyFudge := 1;
        --  end if;
        --  
        --  vn_OverageFudge := pi_Best.totals.qty_asg_overage * 1.10;
        --  if vn_OverageFudge < 20
        --  then vn_OverageFudge := vn_OverageFudge;
        --  end if;
        --  
        --  if (pi_Curr.totals.rating_asg_future
        --          > pi_Best.totals.rating_asg_future
        --      and
        --      pi_Curr.totals.qty_asg_overage
        --          < pi_Best.totals.qty_asg_overage )
        --  or (pi_Curr.totals.qty_asg_future >= vn_FutureQtyFudge
        --      and -- CONTINUE HERE THIS COMPROMISED THE DATE RANGE CHECK !!
        --      pi_Curr.totals.qty_asg_overage < pi_Best.totals.qty_asg_overage )
        --  or (pi_Curr.totals.rating_asg_future > pi_Best.totals.rating_asg_future
        --      and
        --      pi_Curr.totals.qty_asg_overage < vn_OverageFudge )
        --  then return true;
        --  end if;
        --end;
        
        RETURN FALSE;
      END; -- CurrentResultIsBetter
      
      ----------------------------------------------------------
      -- Returns the "best" matrix to satisfy existing requirements.
      -- This is based on a given number of runs.
      -- 
      -- The "best" matrix is:
      -- A) For days <= pi_BusinessDaysAhead  (including past-due days),
      --    we assign cuts on day-by-day basis, which means we do
      --    not optimize into future days until the current date is done
      -- B) For days "in the future" (e.g. ahead of pi_BusinessDaysAhead)
      --    then we do optimization of days-vs-quantity rating (future)
      -- 
      -- PRE-CONDITIONS:
      -- : The reco_rstx_cutcalc_daily table must be full of requirements
      --   based on length-and-day. These requirements fall within
      --   a certain number of business-days-ahead of the current cut
      --   day.
      -- : The reco_rstx_cutcalc_future table must be full of requirements
      --   based on length for all days in "future" range. The future
      --   requirements are ahead of the "business-days-ahead" range
      -- : The reco_rstx_sortedcut table must be full of approved matrices.
      --   They are sorted longest-to-shortest, and don't include rare lens
      --   Note that reco_rstx_sortedcut should reflect actual matrices,
      --   in the reco_rstx_cutmtx table. There may be duplicate
      --   matrices, that is okay.
      -- : The vr_BlankLenAsg and vr_BlankResult should be set properly
      FUNCTION bestmtx_for_typedateqty (pi_GivenQtyRuns IN number)
      RETURN rec_Result
      IS
        vr_TmpResult rec_Result; -- Current loop calcs/results
        vr_BestResult rec_Result; -- Best/Output calcs/results
        
        vb_FoundBest BOOLEAN;
      BEGIN -- bestmtx_for_typedateqty
        vr_BestResult := vr_BlankResult;
        vb_FoundBest := FALSE;
        
        FOR rec_Mtx IN -- loop for each matrix available
          (
            SELECT  mtxSubQ.qtypcs,
                    NVL(mtxSubQ.pc1len,0) p1len,
                    NVL(mtxSubQ.pc1pun,'S') p1pun,
                    NVL(lenreq1.qty_req_dayminus3,0) p1dminus3,
                    NVL(lenreq1.qty_req_dayminus2,0) p1dminus2,
                    NVL(lenreq1.qty_req_dayminus1,0) p1dminus1,
                    NVL(lenreq1.qty_req_today,0) p1today,
                    NVL(lenreq1.qty_req_tomorrow,0) p1tomm,
                    NVL(lenreq1.qty_req_day2,0) p1d2,
                    NVL(lenreq1.qty_req_day3,0) p1d3,
                    NVL(lenreq1.qty_req_day4,0) p1d4,
                    NVL(lenreq1.qty_req_day5,0) p1d5,
                    NVL(lenreq1.qty_req_day6,0) p1d6,
                    NVL(lenreq1.qty_req_day7,0) p1d7,
                    NVL(lenreq1.qty_req_day8,0) p1d8,
                    NVL(lenreq1.qty_req_day9,0) p1d9,
                    NVL(lenreq1.qty_req_day10,0) p1d10,
                    NVL(mtxSubQ.pc2len,0) p2len,
                    NVL(mtxSubQ.pc2pun,'S') p2pun,
                    NVL(lenreq2.qty_req_dayminus3,0) p2dminus3,
                    NVL(lenreq2.qty_req_dayminus2,0) p2dminus2,
                    NVL(lenreq2.qty_req_dayminus1,0) p2dminus1,
                    NVL(lenreq2.qty_req_today,0) p2today,
                    NVL(lenreq2.qty_req_tomorrow,0) p2tomm,
                    NVL(lenreq2.qty_req_day2,0) p2d2,
                    NVL(lenreq2.qty_req_day3,0) p2d3,
                    NVL(lenreq2.qty_req_day4,0) p2d4,
                    NVL(lenreq2.qty_req_day5,0) p2d5,
                    NVL(lenreq2.qty_req_day6,0) p2d6,
                    NVL(lenreq2.qty_req_day7,0) p2d7,
                    NVL(lenreq2.qty_req_day8,0) p2d8,
                    NVL(lenreq2.qty_req_day9,0) p2d9,
                    NVL(lenreq2.qty_req_day10,0) p2d10,
                    NVL(mtxSubQ.pc3len,0) p3len,
                    NVL(mtxSubQ.pc3pun,'S') p3pun,
                    NVL(lenreq3.qty_req_dayminus3,0) p3dminus3,
                    NVL(lenreq3.qty_req_dayminus2,0) p3dminus2,
                    NVL(lenreq3.qty_req_dayminus1,0) p3dminus1,
                    NVL(lenreq3.qty_req_today,0) p3today,
                    NVL(lenreq3.qty_req_tomorrow,0) p3tomm,
                    NVL(lenreq3.qty_req_day2,0) p3d2,
                    NVL(lenreq3.qty_req_day3,0) p3d3,
                    NVL(lenreq3.qty_req_day4,0) p3d4,
                    NVL(lenreq3.qty_req_day5,0) p3d5,
                    NVL(lenreq3.qty_req_day6,0) p3d6,
                    NVL(lenreq3.qty_req_day7,0) p3d7,
                    NVL(lenreq3.qty_req_day8,0) p3d8,
                    NVL(lenreq3.qty_req_day9,0) p3d9,
                    NVL(lenreq3.qty_req_day10,0) p3d10,
                    NVL(mtxSubQ.pc4len,0) p4len,
                    NVL(mtxSubQ.pc4pun,'S') p4pun,
                    NVL(lenreq4.qty_req_dayminus3,0) p4dminus3,
                    NVL(lenreq4.qty_req_dayminus2,0) p4dminus2,
                    NVL(lenreq4.qty_req_dayminus1,0) p4dminus1,
                    NVL(lenreq4.qty_req_today,0) p4today,
                    NVL(lenreq4.qty_req_tomorrow,0) p4tomm,
                    NVL(lenreq4.qty_req_day2,0) p4d2,
                    NVL(lenreq4.qty_req_day3,0) p4d3,
                    NVL(lenreq4.qty_req_day4,0) p4d4,
                    NVL(lenreq4.qty_req_day5,0) p4d5,
                    NVL(lenreq4.qty_req_day6,0) p4d6,
                    NVL(lenreq4.qty_req_day7,0) p4d7,
                    NVL(lenreq4.qty_req_day8,0) p4d8,
                    NVL(lenreq4.qty_req_day9,0) p4d9,
                    NVL(lenreq4.qty_req_day10,0) p4d10
            FROM  reco_rstx_cutcalc_daily lenreq1,
                  reco_rstx_cutcalc_daily lenreq2,
                  reco_rstx_cutcalc_daily lenreq3,
                  reco_rstx_cutcalc_daily lenreq4,
                  (
                    SELECT DISTINCT
                            sortcut.qtypcs,
                            sortcut.pc1len,
                            NVL(lenpunmap1.thepunch,'S') pc1pun,
                            sortcut.pc2len,
                            NVL(lenpunmap2.thepunch,'S') pc2pun,
                            sortcut.pc3len,
                            NVL(lenpunmap3.thepunch,'S') pc3pun,
                            sortcut.pc4len,
                            NVL(lenpunmap4.thepunch,'S') pc4pun
                    FROM  reco_rstx_sortedcut sortcut,
                          reco_rstx_cutmtx_lenpunmap lenpunmap1,
                          reco_rstx_cutmtx_lenpunmap lenpunmap2,
                          reco_rstx_cutmtx_lenpunmap lenpunmap3,
                          reco_rstx_cutmtx_lenpunmap lenpunmap4
                    WHERE   sortcut.pc1len = lenpunmap1.thelength (+)
                    AND     lenpunmap1.thetype (+) = pi_CurrentPartType
                    AND     sortcut.pc2len = lenpunmap2.thelength (+)
                    AND     lenpunmap2.thetype (+) = pi_CurrentPartType
                    AND     sortcut.pc3len = lenpunmap3.thelength (+)
                    AND     lenpunmap3.thetype (+) = pi_CurrentPartType
                    AND     sortcut.pc4len = lenpunmap4.thelength (+)
                    AND     lenpunmap4.thetype (+) = pi_CurrentPartType
                  ) mtxSubQ
            WHERE   mtxSubQ.pc1len = lenreq1.thelength (+)
            AND     mtxSubQ.pc1pun = lenreq1.thepunch (+)
            AND     mtxSubQ.pc2len = lenreq2.thelength (+)
            AND     mtxSubQ.pc2pun = lenreq2.thepunch (+)
            AND     mtxSubQ.pc3len = lenreq3.thelength (+)
            AND     mtxSubQ.pc3pun = lenreq3.thepunch (+)
            AND     mtxSubQ.pc4len = lenreq4.thelength (+)
            AND     mtxSubQ.pc4pun = lenreq4.thepunch (+)
          )
        LOOP
          
          vr_TmpResult := vr_BlankResult;
          
          vr_TmpResult.qtypcs := rec_Mtx.qtypcs;
          
          FOR pceCtr IN 1 .. rec_Mtx.qtypcs -- loop for each part in current mtx
          LOOP
            DECLARE
              vn_IgnoreReqQty number;
              vn_QtyToApply number;
              
              vn_CurrPceLen reco_rstx_cutreqv2.reqlength%TYPE;
              vc_CurrPcePun reco_rstx_cutreqv2.reqpunch%TYPE;
              
              vn_CurrQtyReqDMinus3 number; vn_CurrQtyAsgDMinus3 number;
              vn_CurrQtyReqDMinus2 number; vn_CurrQtyAsgDMinus2 number;
              vn_CurrQtyReqDMinus1 number; vn_CurrQtyAsgDMinus1 number;
              vn_CurrQtyReqToday number; vn_CurrQtyAsgToday number;
              vn_CurrQtyReqTomm number; vn_CurrQtyAsgTomm number;
              vn_CurrQtyReqDay2 number; vn_CurrQtyAsgDay2 number;
              vn_CurrQtyReqDay3 number; vn_CurrQtyAsgDay3 number;
              vn_CurrQtyReqDay4 number; vn_CurrQtyAsgDay4 number;
              vn_CurrQtyReqDay5 number; vn_CurrQtyAsgDay5 number;
              vn_CurrQtyReqDay6 number; vn_CurrQtyAsgDay6 number;
              vn_CurrQtyReqDay7 number; vn_CurrQtyAsgDay7 number;
              vn_CurrQtyReqDay8 number; vn_CurrQtyAsgDay8 number;
              vn_CurrQtyReqDay9 number; vn_CurrQtyAsgDay9 number;
              vn_CurrQtyReqDay10 number; vn_CurrQtyAsgDay10 number;
                                        vn_CurrQtyAsgFutu number;
                                        vn_CurrRateAsgFutu number;
                                        vn_CurrQtyOverage number;
              
            BEGIN
              
              vn_IgnoreReqQty := 0;
              
              IF pceCtr = 2
              THEN
                IF rec_Mtx.p2len = rec_Mtx.p1len
                AND rec_Mtx.p2pun = rec_Mtx.p1pun
                THEN
                  vn_IgnoreReqQty :=
                    vn_IgnoreReqQty + pi_GivenQtyRuns;
                END IF;
              ELSIF pceCtr = 3
              THEN
                IF rec_Mtx.p3len = rec_Mtx.p1len
                AND rec_Mtx.p3pun = rec_Mtx.p1pun
                THEN
                  vn_IgnoreReqQty :=
                    vn_IgnoreReqQty + pi_GivenQtyRuns;
                END IF;
                
                IF rec_Mtx.p3len = rec_Mtx.p2len
                AND rec_Mtx.p3pun = rec_Mtx.p2pun
                THEN
                  vn_IgnoreReqQty :=
                    vn_IgnoreReqQty + pi_GivenQtyRuns;
                END IF;
              ELSIF pceCtr = 4
              THEN
                IF rec_Mtx.p4len = rec_Mtx.p1len
                AND rec_Mtx.p4pun = rec_Mtx.p1pun
                THEN
                  vn_IgnoreReqQty :=
                    vn_IgnoreReqQty + pi_GivenQtyRuns;
                END IF;
                
                IF rec_Mtx.p4len = rec_Mtx.p2len
                AND rec_Mtx.p4pun = rec_Mtx.p2pun
                THEN
                  vn_IgnoreReqQty :=
                    vn_IgnoreReqQty + pi_GivenQtyRuns;
                END IF;
                
                IF rec_Mtx.p4len = rec_Mtx.p3len
                AND rec_Mtx.p4pun = rec_Mtx.p3pun
                THEN
                  vn_IgnoreReqQty :=
                    vn_IgnoreReqQty + pi_GivenQtyRuns;
                END IF;
              END IF;
              
              vn_QtyToApply := pi_GivenQtyRuns;
              
              IF pceCtr = 1
              THEN
                vn_CurrPceLen := rec_Mtx.p1len;
                vc_CurrPcePun := rec_Mtx.p1pun;
              ELSIF pceCtr = 2
              THEN
                vn_CurrPceLen := rec_Mtx.p2len;
                vc_CurrPcePun := rec_Mtx.p2pun;
              ELSIF pceCtr = 3
              THEN
                vn_CurrPceLen := rec_Mtx.p3len;
                vc_CurrPcePun := rec_Mtx.p3pun;
              ELSIF pceCtr = 4
              THEN
                vn_CurrPceLen := rec_Mtx.p4len;
                vc_CurrPcePun := rec_Mtx.p4pun;
              END IF;
              
              IF pceCtr = 1
              THEN
                vn_CurrQtyReqDMinus3 := rec_Mtx.p1dminus3;
                vn_CurrQtyReqDMinus2 := rec_Mtx.p1dminus2;
                vn_CurrQtyReqDMinus1 := rec_Mtx.p1dminus1;
                vn_CurrQtyReqToday := rec_Mtx.p1today;
                vn_CurrQtyReqTomm := rec_Mtx.p1tomm;
                vn_CurrQtyReqDay2 := rec_Mtx.p1d2;
                vn_CurrQtyReqDay3 := rec_Mtx.p1d3;
                vn_CurrQtyReqDay4 := rec_Mtx.p1d4;
                vn_CurrQtyReqDay5 := rec_Mtx.p1d5;
                vn_CurrQtyReqDay6 := rec_Mtx.p1d6;
                vn_CurrQtyReqDay7 := rec_Mtx.p1d7;
                vn_CurrQtyReqDay8 := rec_Mtx.p1d8;
                vn_CurrQtyReqDay9 := rec_Mtx.p1d9;
                vn_CurrQtyReqDay10 := rec_Mtx.p1d10;
              ELSIF pceCtr = 2
              THEN
                vn_CurrQtyReqDMinus3 := rec_Mtx.p2dminus3;
                vn_CurrQtyReqDMinus2 := rec_Mtx.p2dminus2;
                vn_CurrQtyReqDMinus1 := rec_Mtx.p2dminus1;
                vn_CurrQtyReqToday := rec_Mtx.p2today;
                vn_CurrQtyReqTomm := rec_Mtx.p2tomm;
                vn_CurrQtyReqDay2 := rec_Mtx.p2d2;
                vn_CurrQtyReqDay3 := rec_Mtx.p2d3;
                vn_CurrQtyReqDay4 := rec_Mtx.p2d4;
                vn_CurrQtyReqDay5 := rec_Mtx.p2d5;
                vn_CurrQtyReqDay6 := rec_Mtx.p2d6;
                vn_CurrQtyReqDay7 := rec_Mtx.p2d7;
                vn_CurrQtyReqDay8 := rec_Mtx.p2d8;
                vn_CurrQtyReqDay9 := rec_Mtx.p2d9;
                vn_CurrQtyReqDay10 := rec_Mtx.p2d10;
              ELSIF pceCtr = 3
              THEN
                vn_CurrQtyReqDMinus3 := rec_Mtx.p3dminus3;
                vn_CurrQtyReqDMinus2 := rec_Mtx.p3dminus2;
                vn_CurrQtyReqDMinus1 := rec_Mtx.p3dminus1;
                vn_CurrQtyReqToday := rec_Mtx.p3today;
                vn_CurrQtyReqTomm := rec_Mtx.p3tomm;
                vn_CurrQtyReqDay2 := rec_Mtx.p3d2;
                vn_CurrQtyReqDay3 := rec_Mtx.p3d3;
                vn_CurrQtyReqDay4 := rec_Mtx.p3d4;
                vn_CurrQtyReqDay5 := rec_Mtx.p3d5;
                vn_CurrQtyReqDay6 := rec_Mtx.p3d6;
                vn_CurrQtyReqDay7 := rec_Mtx.p3d7;
                vn_CurrQtyReqDay8 := rec_Mtx.p3d8;
                vn_CurrQtyReqDay9 := rec_Mtx.p3d9;
                vn_CurrQtyReqDay10 := rec_Mtx.p3d10;
              ELSIF pceCtr = 4
              THEN
                vn_CurrQtyReqDMinus3 := rec_Mtx.p4dminus3;
                vn_CurrQtyReqDMinus2 := rec_Mtx.p4dminus2;
                vn_CurrQtyReqDMinus1 := rec_Mtx.p4dminus1;
                vn_CurrQtyReqToday := rec_Mtx.p4today;
                vn_CurrQtyReqTomm := rec_Mtx.p4tomm;
                vn_CurrQtyReqDay2 := rec_Mtx.p4d2;
                vn_CurrQtyReqDay3 := rec_Mtx.p4d3;
                vn_CurrQtyReqDay4 := rec_Mtx.p4d4;
                vn_CurrQtyReqDay5 := rec_Mtx.p4d5;
                vn_CurrQtyReqDay6 := rec_Mtx.p4d6;
                vn_CurrQtyReqDay7 := rec_Mtx.p4d7;
                vn_CurrQtyReqDay8 := rec_Mtx.p4d8;
                vn_CurrQtyReqDay9 := rec_Mtx.p4d9;
                vn_CurrQtyReqDay10 := rec_Mtx.p4d10;
              END IF;
              
              vn_CurrQtyAsgDMinus3 := 0; vn_CurrQtyAsgDMinus2 := 0;
              vn_CurrQtyAsgDMinus1 := 0; vn_CurrQtyAsgToday := 0;
              vn_CurrQtyAsgTomm := 0; vn_CurrQtyAsgDay2 := 0;
              vn_CurrQtyAsgDay3 := 0; vn_CurrQtyAsgDay4 := 0;
              vn_CurrQtyAsgDay5 := 0; vn_CurrQtyAsgDay6 := 0;
              vn_CurrQtyAsgDay7 := 0; vn_CurrQtyAsgDay8 := 0;
              vn_CurrQtyAsgDay9 := 0; vn_CurrQtyAsgDay10 := 0;
              vn_CurrQtyAsgFutu := 0;
              vn_CurrRateAsgFutu := 0;
              vn_CurrQtyOverage := 0;
              
              IF vn_QtyToApply > 0 AND vn_CurrQtyReqDMinus3 > 0
              THEN
                IF vn_IgnoreReqQty = 0 AND vn_CurrQtyReqDMinus3 <= vn_QtyToApply
                THEN
                  vn_CurrQtyAsgDMinus3 := vn_CurrQtyReqDMinus3;
                  vn_QtyToApply := vn_QtyToApply - vn_CurrQtyReqDMinus3;
                ELSIF vn_IgnoreReqQty = 0 AND vn_CurrQtyReqDMinus3 > vn_QtyToApply
                THEN
                  vn_CurrQtyAsgDMinus3 := vn_QtyToApply;
                  vn_QtyToApply := 0;
                ELSIF vn_IgnoreReqQty > 0 AND vn_CurrQtyReqDMinus3 <= vn_IgnoreReqQty
                THEN
                  vn_IgnoreReqQty := vn_IgnoreReqQty - vn_CurrQtyReqDMinus3;
                ELSIF vn_IgnoreReqQty > 0 AND vn_CurrQtyReqDMinus3 > vn_IgnoreReqQty
                THEN
                  IF vn_CurrQtyReqDMinus3 - vn_IgnoreReqQty <= vn_QtyToApply
                  THEN
                    vn_CurrQtyAsgDMinus3 := vn_CurrQtyReqDMinus3 - vn_IgnoreReqQty;
                    vn_QtyToApply := vn_QtyToApply
                                      - (vn_CurrQtyReqDMinus3 - vn_IgnoreReqQty);
                  ELSIF vn_CurrQtyReqDMinus3 - vn_IgnoreReqQty > vn_QtyToApply
                  THEN
                    vn_CurrQtyAsgDMinus3 := vn_QtyToApply;
                    vn_QtyToApply := 0;
                  END IF;
                  
                  vn_IgnoreReqQty := 0;
                END IF;
              END IF;
              
              IF vn_QtyToApply > 0 AND vn_CurrQtyReqDMinus2 > 0
              THEN
                IF vn_IgnoreReqQty = 0 AND vn_CurrQtyReqDMinus2 <= vn_QtyToApply
                THEN
                  vn_CurrQtyAsgDMinus2 := vn_CurrQtyReqDMinus2;
                  vn_QtyToApply := vn_QtyToApply - vn_CurrQtyReqDMinus2;
                ELSIF vn_IgnoreReqQty = 0 AND vn_CurrQtyReqDMinus2 > vn_QtyToApply
                THEN
                  vn_CurrQtyAsgDMinus2 := vn_QtyToApply;
                  vn_QtyToApply := 0;
                ELSIF vn_IgnoreReqQty > 0 AND vn_CurrQtyReqDMinus2 <= vn_IgnoreReqQty
                THEN
                  vn_IgnoreReqQty := vn_IgnoreReqQty - vn_CurrQtyReqDMinus2;
                ELSIF vn_IgnoreReqQty > 0 AND vn_CurrQtyReqDMinus2 > vn_IgnoreReqQty
                THEN
                  IF vn_CurrQtyReqDMinus2 - vn_IgnoreReqQty <= vn_QtyToApply
                  THEN
                    vn_CurrQtyAsgDMinus2 := vn_CurrQtyReqDMinus2 - vn_IgnoreReqQty;
                    vn_QtyToApply := vn_QtyToApply
                                      - (vn_CurrQtyReqDMinus2 - vn_IgnoreReqQty);
                  ELSIF vn_CurrQtyReqDMinus2 - vn_IgnoreReqQty > vn_QtyToApply
                  THEN
                    vn_CurrQtyAsgDMinus2 := vn_QtyToApply;
                    vn_QtyToApply := 0;
                  END IF;
                  
                  vn_IgnoreReqQty := 0;
                END IF;
              END IF;
              
              IF vn_QtyToApply > 0 AND vn_CurrQtyReqDMinus1 > 0
              THEN
                IF vn_IgnoreReqQty = 0 AND vn_CurrQtyReqDMinus1 <= vn_QtyToApply
                THEN
                  vn_CurrQtyAsgDMinus1 := vn_CurrQtyReqDMinus1;
                  vn_QtyToApply := vn_QtyToApply - vn_CurrQtyReqDMinus1;
                ELSIF vn_IgnoreReqQty = 0 AND vn_CurrQtyReqDMinus1 > vn_QtyToApply
                THEN
                  vn_CurrQtyAsgDMinus1 := vn_QtyToApply;
                  vn_QtyToApply := 0;
                ELSIF vn_IgnoreReqQty > 0 AND vn_CurrQtyReqDMinus1 <= vn_IgnoreReqQty
                THEN
                  vn_IgnoreReqQty := vn_IgnoreReqQty - vn_CurrQtyReqDMinus1;
                ELSIF vn_IgnoreReqQty > 0 AND vn_CurrQtyReqDMinus1 > vn_IgnoreReqQty
                THEN
                  IF vn_CurrQtyReqDMinus1 - vn_IgnoreReqQty <= vn_QtyToApply
                  THEN
                    vn_CurrQtyAsgDMinus1 := vn_CurrQtyReqDMinus1 - vn_IgnoreReqQty;
                    vn_QtyToApply := vn_QtyToApply
                                      - (vn_CurrQtyReqDMinus1 - vn_IgnoreReqQty);
                  ELSIF vn_CurrQtyReqDMinus1 - vn_IgnoreReqQty > vn_QtyToApply
                  THEN
                    vn_CurrQtyAsgDMinus1 := vn_QtyToApply;
                    vn_QtyToApply := 0;
                  END IF;
                  
                  vn_IgnoreReqQty := 0;
                END IF;
              END IF;
              
              IF vn_QtyToApply > 0 AND vn_CurrQtyReqToday > 0
              THEN
                IF vn_IgnoreReqQty = 0 AND vn_CurrQtyReqToday <= vn_QtyToApply
                THEN
                  vn_CurrQtyAsgToday := vn_CurrQtyReqToday;
                  vn_QtyToApply := vn_QtyToApply - vn_CurrQtyReqToday;
                ELSIF vn_IgnoreReqQty = 0 AND vn_CurrQtyReqToday > vn_QtyToApply
                THEN
                  vn_CurrQtyAsgToday := vn_QtyToApply;
                  vn_QtyToApply := 0;
                ELSIF vn_IgnoreReqQty > 0 AND vn_CurrQtyReqToday <= vn_IgnoreReqQty
                THEN
                  vn_IgnoreReqQty := vn_IgnoreReqQty - vn_CurrQtyReqToday;
                ELSIF vn_IgnoreReqQty > 0 AND vn_CurrQtyReqToday > vn_IgnoreReqQty
                THEN
                  IF vn_CurrQtyReqToday - vn_IgnoreReqQty <= vn_QtyToApply
                  THEN
                    vn_CurrQtyAsgToday := vn_CurrQtyReqToday - vn_IgnoreReqQty;
                    vn_QtyToApply := vn_QtyToApply
                                      - (vn_CurrQtyReqToday - vn_IgnoreReqQty);
                  ELSIF vn_CurrQtyReqToday - vn_IgnoreReqQty > vn_QtyToApply
                  THEN
                    vn_CurrQtyAsgToday := vn_QtyToApply;
                    vn_QtyToApply := 0;
                  END IF;
                  
                  vn_IgnoreReqQty := 0;
                END IF;
              END IF;
              
              IF vn_QtyToApply > 0 AND vn_CurrQtyReqTomm > 0
              THEN
                IF vn_IgnoreReqQty = 0 AND vn_CurrQtyReqTomm <= vn_QtyToApply
                THEN
                  vn_CurrQtyAsgTomm := vn_CurrQtyReqTomm;
                  vn_QtyToApply := vn_QtyToApply - vn_CurrQtyReqTomm;
                ELSIF vn_IgnoreReqQty = 0 AND vn_CurrQtyReqTomm > vn_QtyToApply
                THEN
                  vn_CurrQtyAsgTomm := vn_QtyToApply;
                  vn_QtyToApply := 0;
                ELSIF vn_IgnoreReqQty > 0 AND vn_CurrQtyReqTomm <= vn_IgnoreReqQty
                THEN
                  vn_IgnoreReqQty := vn_IgnoreReqQty - vn_CurrQtyReqTomm;
                ELSIF vn_IgnoreReqQty > 0 AND vn_CurrQtyReqTomm > vn_IgnoreReqQty
                THEN
                  IF vn_CurrQtyReqTomm - vn_IgnoreReqQty <= vn_QtyToApply
                  THEN
                    vn_CurrQtyAsgTomm := vn_CurrQtyReqTomm - vn_IgnoreReqQty;
                    vn_QtyToApply := vn_QtyToApply
                                      - (vn_CurrQtyReqTomm - vn_IgnoreReqQty);
                  ELSIF vn_CurrQtyReqTomm - vn_IgnoreReqQty > vn_QtyToApply
                  THEN
                    vn_CurrQtyAsgTomm := vn_QtyToApply;
                    vn_QtyToApply := 0;
                  END IF;
                  
                  vn_IgnoreReqQty := 0;
                END IF;
              END IF;
              
              IF vn_QtyToApply > 0 AND vn_CurrQtyReqDay2 > 0
              THEN
                IF vn_IgnoreReqQty = 0 AND vn_CurrQtyReqDay2 <= vn_QtyToApply
                THEN
                  vn_CurrQtyAsgDay2 := vn_CurrQtyReqDay2;
                  vn_QtyToApply := vn_QtyToApply - vn_CurrQtyReqDay2;
                ELSIF vn_IgnoreReqQty = 0 AND vn_CurrQtyReqDay2 > vn_QtyToApply
                THEN
                  vn_CurrQtyAsgDay2 := vn_QtyToApply;
                  vn_QtyToApply := 0;
                ELSIF vn_IgnoreReqQty > 0 AND vn_CurrQtyReqDay2 <= vn_IgnoreReqQty
                THEN
                  vn_IgnoreReqQty := vn_IgnoreReqQty - vn_CurrQtyReqDay2;
                ELSIF vn_IgnoreReqQty > 0 AND vn_CurrQtyReqDay2 > vn_IgnoreReqQty
                THEN
                  IF vn_CurrQtyReqDay2 - vn_IgnoreReqQty <= vn_QtyToApply
                  THEN
                    vn_CurrQtyAsgDay2 := vn_CurrQtyReqDay2 - vn_IgnoreReqQty;
                    vn_QtyToApply := vn_QtyToApply
                                      - (vn_CurrQtyReqDay2 - vn_IgnoreReqQty);
                  ELSIF vn_CurrQtyReqDay2 - vn_IgnoreReqQty > vn_QtyToApply
                  THEN
                    vn_CurrQtyAsgDay2 := vn_QtyToApply;
                    vn_QtyToApply := 0;
                  END IF;
                  
                  vn_IgnoreReqQty := 0;
                END IF;
              END IF;
              
              IF vn_QtyToApply > 0 AND vn_CurrQtyReqDay3 > 0
              THEN
                IF vn_IgnoreReqQty = 0 AND vn_CurrQtyReqDay3 <= vn_QtyToApply
                THEN
                  vn_CurrQtyAsgDay3 := vn_CurrQtyReqDay3;
                  vn_QtyToApply := vn_QtyToApply - vn_CurrQtyReqDay3;
                ELSIF vn_IgnoreReqQty = 0 AND vn_CurrQtyReqDay3 > vn_QtyToApply
                THEN
                  vn_CurrQtyAsgDay3 := vn_QtyToApply;
                  vn_QtyToApply := 0;
                ELSIF vn_IgnoreReqQty > 0 AND vn_CurrQtyReqDay3 <= vn_IgnoreReqQty
                THEN
                  vn_IgnoreReqQty := vn_IgnoreReqQty - vn_CurrQtyReqDay3;
                ELSIF vn_IgnoreReqQty > 0 AND vn_CurrQtyReqDay3 > vn_IgnoreReqQty
                THEN
                  IF vn_CurrQtyReqDay3 - vn_IgnoreReqQty <= vn_QtyToApply
                  THEN
                    vn_CurrQtyAsgDay3 := vn_CurrQtyReqDay3 - vn_IgnoreReqQty;
                    vn_QtyToApply := vn_QtyToApply
                                      - (vn_CurrQtyReqDay3 - vn_IgnoreReqQty);
                  ELSIF vn_CurrQtyReqDay3 - vn_IgnoreReqQty > vn_QtyToApply
                  THEN
                    vn_CurrQtyAsgDay3 := vn_QtyToApply;
                    vn_QtyToApply := 0;
                  END IF;
                  
                  vn_IgnoreReqQty := 0;
                END IF;
              END IF;
              
              IF vn_QtyToApply > 0 AND vn_CurrQtyReqDay4 > 0
              THEN
                IF vn_IgnoreReqQty = 0 AND vn_CurrQtyReqDay4 <= vn_QtyToApply
                THEN
                  vn_CurrQtyAsgDay4 := vn_CurrQtyReqDay4;
                  vn_QtyToApply := vn_QtyToApply - vn_CurrQtyReqDay4;
                ELSIF vn_IgnoreReqQty = 0 AND vn_CurrQtyReqDay4 > vn_QtyToApply
                THEN
                  vn_CurrQtyAsgDay4 := vn_QtyToApply;
                  vn_QtyToApply := 0;
                ELSIF vn_IgnoreReqQty > 0 AND vn_CurrQtyReqDay4 <= vn_IgnoreReqQty
                THEN
                  vn_IgnoreReqQty := vn_IgnoreReqQty - vn_CurrQtyReqDay4;
                ELSIF vn_IgnoreReqQty > 0 AND vn_CurrQtyReqDay4 > vn_IgnoreReqQty
                THEN
                  IF vn_CurrQtyReqDay4 - vn_IgnoreReqQty <= vn_QtyToApply
                  THEN
                    vn_CurrQtyAsgDay4 := vn_CurrQtyReqDay4 - vn_IgnoreReqQty;
                    vn_QtyToApply := vn_QtyToApply
                                      - (vn_CurrQtyReqDay4 - vn_IgnoreReqQty);
                  ELSIF vn_CurrQtyReqDay4 - vn_IgnoreReqQty > vn_QtyToApply
                  THEN
                    vn_CurrQtyAsgDay4 := vn_QtyToApply;
                    vn_QtyToApply := 0;
                  END IF;
                  
                  vn_IgnoreReqQty := 0;
                END IF;
              END IF;
              
              IF vn_QtyToApply > 0 AND vn_CurrQtyReqDay5 > 0
              THEN
                IF vn_IgnoreReqQty = 0 AND vn_CurrQtyReqDay5 <= vn_QtyToApply
                THEN
                  vn_CurrQtyAsgDay5 := vn_CurrQtyReqDay5;
                  vn_QtyToApply := vn_QtyToApply - vn_CurrQtyReqDay5;
                ELSIF vn_IgnoreReqQty = 0 AND vn_CurrQtyReqDay5 > vn_QtyToApply
                THEN
                  vn_CurrQtyAsgDay5 := vn_QtyToApply;
                  vn_QtyToApply := 0;
                ELSIF vn_IgnoreReqQty > 0 AND vn_CurrQtyReqDay5 <= vn_IgnoreReqQty
                THEN
                  vn_IgnoreReqQty := vn_IgnoreReqQty - vn_CurrQtyReqDay5;
                ELSIF vn_IgnoreReqQty > 0 AND vn_CurrQtyReqDay5 > vn_IgnoreReqQty
                THEN
                  IF vn_CurrQtyReqDay5 - vn_IgnoreReqQty <= vn_QtyToApply
                  THEN
                    vn_CurrQtyAsgDay5 := vn_CurrQtyReqDay5 - vn_IgnoreReqQty;
                    vn_QtyToApply := vn_QtyToApply
                                      - (vn_CurrQtyReqDay5 - vn_IgnoreReqQty);
                  ELSIF vn_CurrQtyReqDay5 - vn_IgnoreReqQty > vn_QtyToApply
                  THEN
                    vn_CurrQtyAsgDay5 := vn_QtyToApply;
                    vn_QtyToApply := 0;
                  END IF;
                  
                  vn_IgnoreReqQty := 0;
                END IF;
              END IF;
              
              IF vn_QtyToApply > 0 AND vn_CurrQtyReqDay6 > 0
              THEN
                IF vn_IgnoreReqQty = 0 AND vn_CurrQtyReqDay6 <= vn_QtyToApply
                THEN
                  vn_CurrQtyAsgDay6 := vn_CurrQtyReqDay6;
                  vn_QtyToApply := vn_QtyToApply - vn_CurrQtyReqDay6;
                ELSIF vn_IgnoreReqQty = 0 AND vn_CurrQtyReqDay6 > vn_QtyToApply
                THEN
                  vn_CurrQtyAsgDay6 := vn_QtyToApply;
                  vn_QtyToApply := 0;
                ELSIF vn_IgnoreReqQty > 0 AND vn_CurrQtyReqDay6 <= vn_IgnoreReqQty
                THEN
                  vn_IgnoreReqQty := vn_IgnoreReqQty - vn_CurrQtyReqDay6;
                ELSIF vn_IgnoreReqQty > 0 AND vn_CurrQtyReqDay6 > vn_IgnoreReqQty
                THEN
                  IF vn_CurrQtyReqDay6 - vn_IgnoreReqQty <= vn_QtyToApply
                  THEN
                    vn_CurrQtyAsgDay6 := vn_CurrQtyReqDay6 - vn_IgnoreReqQty;
                    vn_QtyToApply := vn_QtyToApply
                                      - (vn_CurrQtyReqDay6 - vn_IgnoreReqQty);
                  ELSIF vn_CurrQtyReqDay6 - vn_IgnoreReqQty > vn_QtyToApply
                  THEN
                    vn_CurrQtyAsgDay6 := vn_QtyToApply;
                    vn_QtyToApply := 0;
                  END IF;
                  
                  vn_IgnoreReqQty := 0;
                END IF;
              END IF;
              
              IF vn_QtyToApply > 0 AND vn_CurrQtyReqDay7 > 0
              THEN
                IF vn_IgnoreReqQty = 0 AND vn_CurrQtyReqDay7 <= vn_QtyToApply
                THEN
                  vn_CurrQtyAsgDay7 := vn_CurrQtyReqDay7;
                  vn_QtyToApply := vn_QtyToApply - vn_CurrQtyReqDay7;
                ELSIF vn_IgnoreReqQty = 0 AND vn_CurrQtyReqDay7 > vn_QtyToApply
                THEN
                  vn_CurrQtyAsgDay7 := vn_QtyToApply;
                  vn_QtyToApply := 0;
                ELSIF vn_IgnoreReqQty > 0 AND vn_CurrQtyReqDay7 <= vn_IgnoreReqQty
                THEN
                  vn_IgnoreReqQty := vn_IgnoreReqQty - vn_CurrQtyReqDay7;
                ELSIF vn_IgnoreReqQty > 0 AND vn_CurrQtyReqDay7 > vn_IgnoreReqQty
                THEN
                  IF vn_CurrQtyReqDay7 - vn_IgnoreReqQty <= vn_QtyToApply
                  THEN
                    vn_CurrQtyAsgDay7 := vn_CurrQtyReqDay7 - vn_IgnoreReqQty;
                    vn_QtyToApply := vn_QtyToApply
                                      - (vn_CurrQtyReqDay7 - vn_IgnoreReqQty);
                  ELSIF vn_CurrQtyReqDay7 - vn_IgnoreReqQty > vn_QtyToApply
                  THEN
                    vn_CurrQtyAsgDay7 := vn_QtyToApply;
                    vn_QtyToApply := 0;
                  END IF;
                  
                  vn_IgnoreReqQty := 0;
                END IF;
              END IF;
              
              IF vn_QtyToApply > 0 AND vn_CurrQtyReqDay8 > 0
              THEN
                IF vn_IgnoreReqQty = 0 AND vn_CurrQtyReqDay8 <= vn_QtyToApply
                THEN
                  vn_CurrQtyAsgDay8 := vn_CurrQtyReqDay8;
                  vn_QtyToApply := vn_QtyToApply - vn_CurrQtyReqDay8;
                ELSIF vn_IgnoreReqQty = 0 AND vn_CurrQtyReqDay8 > vn_QtyToApply
                THEN
                  vn_CurrQtyAsgDay8 := vn_QtyToApply;
                  vn_QtyToApply := 0;
                ELSIF vn_IgnoreReqQty > 0 AND vn_CurrQtyReqDay8 <= vn_IgnoreReqQty
                THEN
                  vn_IgnoreReqQty := vn_IgnoreReqQty - vn_CurrQtyReqDay8;
                ELSIF vn_IgnoreReqQty > 0 AND vn_CurrQtyReqDay8 > vn_IgnoreReqQty
                THEN
                  IF vn_CurrQtyReqDay8 - vn_IgnoreReqQty <= vn_QtyToApply
                  THEN
                    vn_CurrQtyAsgDay8 := vn_CurrQtyReqDay8 - vn_IgnoreReqQty;
                    vn_QtyToApply := vn_QtyToApply
                                      - (vn_CurrQtyReqDay8 - vn_IgnoreReqQty);
                  ELSIF vn_CurrQtyReqDay8 - vn_IgnoreReqQty > vn_QtyToApply
                  THEN
                    vn_CurrQtyAsgDay8 := vn_QtyToApply;
                    vn_QtyToApply := 0;
                  END IF;
                  
                  vn_IgnoreReqQty := 0;
                END IF;
              END IF;
              
              IF vn_QtyToApply > 0 AND vn_CurrQtyReqDay9 > 0
              THEN
                IF vn_IgnoreReqQty = 0 AND vn_CurrQtyReqDay9 <= vn_QtyToApply
                THEN
                  vn_CurrQtyAsgDay9 := vn_CurrQtyReqDay9;
                  vn_QtyToApply := vn_QtyToApply - vn_CurrQtyReqDay9;
                ELSIF vn_IgnoreReqQty = 0 AND vn_CurrQtyReqDay9 > vn_QtyToApply
                THEN
                  vn_CurrQtyAsgDay9 := vn_QtyToApply;
                  vn_QtyToApply := 0;
                ELSIF vn_IgnoreReqQty > 0 AND vn_CurrQtyReqDay9 <= vn_IgnoreReqQty
                THEN
                  vn_IgnoreReqQty := vn_IgnoreReqQty - vn_CurrQtyReqDay9;
                ELSIF vn_IgnoreReqQty > 0 AND vn_CurrQtyReqDay9 > vn_IgnoreReqQty
                THEN
                  IF vn_CurrQtyReqDay9 - vn_IgnoreReqQty <= vn_QtyToApply
                  THEN
                    vn_CurrQtyAsgDay9 := vn_CurrQtyReqDay9 - vn_IgnoreReqQty;
                    vn_QtyToApply := vn_QtyToApply
                                      - (vn_CurrQtyReqDay9 - vn_IgnoreReqQty);
                  ELSIF vn_CurrQtyReqDay9 - vn_IgnoreReqQty > vn_QtyToApply
                  THEN
                    vn_CurrQtyAsgDay9 := vn_QtyToApply;
                    vn_QtyToApply := 0;
                  END IF;
                  
                  vn_IgnoreReqQty := 0;
                END IF;
              END IF;
              
              IF vn_QtyToApply > 0 AND vn_CurrQtyReqDay10 > 0
              THEN
                IF vn_IgnoreReqQty = 0 AND vn_CurrQtyReqDay10 <= vn_QtyToApply
                THEN
                  vn_CurrQtyAsgDay10 := vn_CurrQtyReqDay10;
                  vn_QtyToApply := vn_QtyToApply - vn_CurrQtyReqDay10;
                ELSIF vn_IgnoreReqQty = 0 AND vn_CurrQtyReqDay10 > vn_QtyToApply
                THEN
                  vn_CurrQtyAsgDay10 := vn_QtyToApply;
                  vn_QtyToApply := 0;
                ELSIF vn_IgnoreReqQty > 0 AND vn_CurrQtyReqDay10 <= vn_IgnoreReqQty
                THEN
                  vn_IgnoreReqQty := vn_IgnoreReqQty - vn_CurrQtyReqDay10;
                ELSIF vn_IgnoreReqQty > 0 AND vn_CurrQtyReqDay10 > vn_IgnoreReqQty
                THEN
                  IF vn_CurrQtyReqDay10 - vn_IgnoreReqQty <= vn_QtyToApply
                  THEN
                    vn_CurrQtyAsgDay10 := vn_CurrQtyReqDay10 - vn_IgnoreReqQty;
                    vn_QtyToApply := vn_QtyToApply
                                      - (vn_CurrQtyReqDay10 - vn_IgnoreReqQty);
                  ELSIF vn_CurrQtyReqDay10 - vn_IgnoreReqQty > vn_QtyToApply
                  THEN
                    vn_CurrQtyAsgDay10 := vn_QtyToApply;
                    vn_QtyToApply := 0;
                  END IF;
                  
                  vn_IgnoreReqQty := 0;
                END IF;
              END IF;
              
              vn_CurrQtyAsgFutu := 0;
              vn_CurrRateAsgFutu := 0;
              
              FOR rec_FutureReq IN
                ( SELECT  thelength,
                          thepunch,
                          thedate,
                          qty_remaining qtyRemain
                  FROM reco_rstx_cutcalc_future
                  WHERE thelength = vn_CurrPceLen
                  AND thepunch = vc_CurrPcePun
                  ORDER BY thedate )
              LOOP
                IF vn_QtyToApply = 0
                THEN exit;
                END IF;
                
                IF vn_IgnoreReqQty = 0
                AND rec_FutureReq.qtyRemain <= vn_QtyToApply
                THEN
                  vn_CurrQtyAsgFutu :=
                    vn_CurrQtyAsgFutu + rec_FutureReq.qtyRemain;
                  vn_CurrRateAsgFutu := vn_CurrRateAsgFutu +
                    (
                      CEIL(rec_FutureReq.qtyRemain *
                        POWER(.85,rec_FutureReq.thedate - vd_FirstFutureDay))
                    );
                  vn_QtyToApply := vn_QtyToApply - rec_FutureReq.qtyRemain;
                ELSIF vn_IgnoreReqQty = 0
                AND rec_FutureReq.qtyRemain > vn_QtyToApply
                THEN
                  vn_CurrQtyAsgFutu :=
                    vn_CurrQtyAsgFutu + vn_QtyToApply;
                  vn_CurrRateAsgFutu := vn_CurrRateAsgFutu +
                    (
                      CEIL(vn_QtyToApply *
                        POWER(.85,rec_FutureReq.thedate - vd_FirstFutureDay))
                    );
                  vn_QtyToApply := 0;
                ELSIF vn_IgnoreReqQty > 0
                AND rec_FutureReq.qtyRemain <= vn_IgnoreReqQty
                THEN
                  vn_IgnoreReqQty := vn_IgnoreReqQty - rec_FutureReq.qtyRemain;
                ELSIF vn_IgnoreReqQty > 0
                AND rec_FutureReq.qtyRemain > vn_IgnoreReqQty
                THEN
                  IF rec_FutureReq.qtyRemain - vn_IgnoreReqQty <= vn_QtyToApply
                  THEN
                    vn_CurrQtyAsgFutu :=
                      vn_CurrQtyAsgFutu +
                        (rec_FutureReq.qtyRemain - vn_IgnoreReqQty);
                    vn_CurrRateAsgFutu := vn_CurrRateAsgFutu +
                      (
                        CEIL((rec_FutureReq.qtyRemain - vn_IgnoreReqQty) *
                          POWER(.85,rec_FutureReq.thedate - vd_FirstFutureDay))
                      );
                    vn_QtyToApply := vn_QtyToApply
                                      - (rec_FutureReq.qtyRemain - vn_IgnoreReqQty);
                  ELSIF rec_FutureReq.qtyRemain - vn_IgnoreReqQty > vn_QtyToApply
                  THEN
                    vn_CurrQtyAsgFutu :=
                      vn_CurrQtyAsgFutu + vn_QtyToApply;
                    vn_CurrRateAsgFutu := vn_CurrRateAsgFutu +
                      (
                        CEIL(vn_QtyToApply *
                          POWER(.85,rec_FutureReq.thedate - vd_FirstFutureDay))
                      );
                    vn_QtyToApply := 0;
                  END IF;
                  
                  vn_IgnoreReqQty := 0;
                END IF;
                
                -- Loop to next future requirement
              END LOOP;
              
              vn_CurrQtyOverage := 0;
              
              IF vn_QtyToApply > 0
              THEN
                vn_CurrQtyOverage := vn_QtyToApply;
                vn_QtyToApply := 0;
              END IF;
              
              IF pceCtr = 1
              THEN
                vr_TmpResult.p1len := rec_Mtx.p1len;
                vr_TmpResult.p1pun := rec_Mtx.p1pun;
                vr_TmpResult.p1asgs.qty_asg_dminus3 := vn_CurrQtyAsgDMinus3;
                vr_TmpResult.p1asgs.qty_asg_dminus2 := vn_CurrQtyAsgDMinus2;
                vr_TmpResult.p1asgs.qty_asg_dminus1 := vn_CurrQtyAsgDMinus1;
                vr_TmpResult.p1asgs.qty_asg_today := vn_CurrQtyAsgToday;
                vr_TmpResult.p1asgs.qty_asg_tomorrow := vn_CurrQtyAsgTomm;
                vr_TmpResult.p1asgs.qty_asg_d2 := vn_CurrQtyAsgDay2;
                vr_TmpResult.p1asgs.qty_asg_d3 := vn_CurrQtyAsgDay3;
                vr_TmpResult.p1asgs.qty_asg_d4 := vn_CurrQtyAsgDay4;
                vr_TmpResult.p1asgs.qty_asg_d5 := vn_CurrQtyAsgDay5;
                vr_TmpResult.p1asgs.qty_asg_d6 := vn_CurrQtyAsgDay6;
                vr_TmpResult.p1asgs.qty_asg_d7 := vn_CurrQtyAsgDay7;
                vr_TmpResult.p1asgs.qty_asg_d8 := vn_CurrQtyAsgDay8;
                vr_TmpResult.p1asgs.qty_asg_d9 := vn_CurrQtyAsgDay9;
                vr_TmpResult.p1asgs.qty_asg_d10 := vn_CurrQtyAsgDay10;
                vr_TmpResult.p1asgs.qty_asg_future := vn_CurrQtyAsgFutu;
                vr_TmpResult.p1asgs.rating_asg_future := vn_CurrRateAsgFutu;
                vr_TmpResult.p1asgs.qty_asg_overage := vn_CurrQtyOverage;
              ELSIF pceCtr = 2
              THEN
                vr_TmpResult.p2len := rec_Mtx.p2len;
                vr_TmpResult.p2pun := rec_Mtx.p2pun;
                vr_TmpResult.p2asgs.qty_asg_dminus3 := vn_CurrQtyAsgDMinus3;
                vr_TmpResult.p2asgs.qty_asg_dminus2 := vn_CurrQtyAsgDMinus2;
                vr_TmpResult.p2asgs.qty_asg_dminus1 := vn_CurrQtyAsgDMinus1;
                vr_TmpResult.p2asgs.qty_asg_today := vn_CurrQtyAsgToday;
                vr_TmpResult.p2asgs.qty_asg_tomorrow := vn_CurrQtyAsgTomm;
                vr_TmpResult.p2asgs.qty_asg_d2 := vn_CurrQtyAsgDay2;
                vr_TmpResult.p2asgs.qty_asg_d3 := vn_CurrQtyAsgDay3;
                vr_TmpResult.p2asgs.qty_asg_d4 := vn_CurrQtyAsgDay4;
                vr_TmpResult.p2asgs.qty_asg_d5 := vn_CurrQtyAsgDay5;
                vr_TmpResult.p2asgs.qty_asg_d6 := vn_CurrQtyAsgDay6;
                vr_TmpResult.p2asgs.qty_asg_d7 := vn_CurrQtyAsgDay7;
                vr_TmpResult.p2asgs.qty_asg_d8 := vn_CurrQtyAsgDay8;
                vr_TmpResult.p2asgs.qty_asg_d9 := vn_CurrQtyAsgDay9;
                vr_TmpResult.p2asgs.qty_asg_d10 := vn_CurrQtyAsgDay10;
                vr_TmpResult.p2asgs.qty_asg_future := vn_CurrQtyAsgFutu;
                vr_TmpResult.p2asgs.rating_asg_future := vn_CurrRateAsgFutu;
                vr_TmpResult.p2asgs.qty_asg_overage := vn_CurrQtyOverage;
              ELSIF pceCtr = 3
              THEN
                vr_TmpResult.p3len := rec_Mtx.p3len;
                vr_TmpResult.p3pun := rec_Mtx.p3pun;
                vr_TmpResult.p3asgs.qty_asg_dminus3 := vn_CurrQtyAsgDMinus3;
                vr_TmpResult.p3asgs.qty_asg_dminus2 := vn_CurrQtyAsgDMinus2;
                vr_TmpResult.p3asgs.qty_asg_dminus1 := vn_CurrQtyAsgDMinus1;
                vr_TmpResult.p3asgs.qty_asg_today := vn_CurrQtyAsgToday;
                vr_TmpResult.p3asgs.qty_asg_tomorrow := vn_CurrQtyAsgTomm;
                vr_TmpResult.p3asgs.qty_asg_d2 := vn_CurrQtyAsgDay2;
                vr_TmpResult.p3asgs.qty_asg_d3 := vn_CurrQtyAsgDay3;
                vr_TmpResult.p3asgs.qty_asg_d4 := vn_CurrQtyAsgDay4;
                vr_TmpResult.p3asgs.qty_asg_d5 := vn_CurrQtyAsgDay5;
                vr_TmpResult.p3asgs.qty_asg_d6 := vn_CurrQtyAsgDay6;
                vr_TmpResult.p3asgs.qty_asg_d7 := vn_CurrQtyAsgDay7;
                vr_TmpResult.p3asgs.qty_asg_d8 := vn_CurrQtyAsgDay8;
                vr_TmpResult.p3asgs.qty_asg_d9 := vn_CurrQtyAsgDay9;
                vr_TmpResult.p3asgs.qty_asg_d10 := vn_CurrQtyAsgDay10;
                vr_TmpResult.p3asgs.qty_asg_future := vn_CurrQtyAsgFutu;
                vr_TmpResult.p3asgs.rating_asg_future := vn_CurrRateAsgFutu;
                vr_TmpResult.p3asgs.qty_asg_overage := vn_CurrQtyOverage;
              ELSIF pceCtr = 4
              THEN
                vr_TmpResult.p4len := rec_Mtx.p4len;
                vr_TmpResult.p4pun := rec_Mtx.p4pun;
                vr_TmpResult.p4asgs.qty_asg_dminus3 := vn_CurrQtyAsgDMinus3;
                vr_TmpResult.p4asgs.qty_asg_dminus2 := vn_CurrQtyAsgDMinus2;
                vr_TmpResult.p4asgs.qty_asg_dminus1 := vn_CurrQtyAsgDMinus1;
                vr_TmpResult.p4asgs.qty_asg_today := vn_CurrQtyAsgToday;
                vr_TmpResult.p4asgs.qty_asg_tomorrow := vn_CurrQtyAsgTomm;
                vr_TmpResult.p4asgs.qty_asg_d2 := vn_CurrQtyAsgDay2;
                vr_TmpResult.p4asgs.qty_asg_d3 := vn_CurrQtyAsgDay3;
                vr_TmpResult.p4asgs.qty_asg_d4 := vn_CurrQtyAsgDay4;
                vr_TmpResult.p4asgs.qty_asg_d5 := vn_CurrQtyAsgDay5;
                vr_TmpResult.p4asgs.qty_asg_d6 := vn_CurrQtyAsgDay6;
                vr_TmpResult.p4asgs.qty_asg_d7 := vn_CurrQtyAsgDay7;
                vr_TmpResult.p4asgs.qty_asg_d8 := vn_CurrQtyAsgDay8;
                vr_TmpResult.p4asgs.qty_asg_d9 := vn_CurrQtyAsgDay9;
                vr_TmpResult.p4asgs.qty_asg_d10 := vn_CurrQtyAsgDay10;
                vr_TmpResult.p4asgs.qty_asg_future := vn_CurrQtyAsgFutu;
                vr_TmpResult.p4asgs.rating_asg_future := vn_CurrRateAsgFutu;
                vr_TmpResult.p4asgs.qty_asg_overage := vn_CurrQtyOverage;
              END IF;
            END;
          END LOOP; -- loop for each part in current mtx
          
          vr_TmpResult.totals := vr_BlankLenAsg;
          
          vr_TmpResult.totals.qty_asg_dminus3 :=
            vr_TmpResult.p1asgs.qty_asg_dminus3 +
            vr_TmpResult.p2asgs.qty_asg_dminus3 +
            vr_TmpResult.p3asgs.qty_asg_dminus3 +
            vr_TmpResult.p4asgs.qty_asg_dminus3;
          
          vr_TmpResult.totals.qty_asg_dminus2 :=
            vr_TmpResult.p1asgs.qty_asg_dminus2 +
            vr_TmpResult.p2asgs.qty_asg_dminus2 +
            vr_TmpResult.p3asgs.qty_asg_dminus2 +
            vr_TmpResult.p4asgs.qty_asg_dminus2;
          
          vr_TmpResult.totals.qty_asg_dminus1 :=
            vr_TmpResult.p1asgs.qty_asg_dminus1 +
            vr_TmpResult.p2asgs.qty_asg_dminus1 +
            vr_TmpResult.p3asgs.qty_asg_dminus1 +
            vr_TmpResult.p4asgs.qty_asg_dminus1;
          
          vr_TmpResult.totals.qty_asg_today :=
            vr_TmpResult.p1asgs.qty_asg_today +
            vr_TmpResult.p2asgs.qty_asg_today +
            vr_TmpResult.p3asgs.qty_asg_today +
            vr_TmpResult.p4asgs.qty_asg_today;
          
          vr_TmpResult.totals.qty_asg_tomorrow :=
            vr_TmpResult.p1asgs.qty_asg_tomorrow +
            vr_TmpResult.p2asgs.qty_asg_tomorrow +
            vr_TmpResult.p3asgs.qty_asg_tomorrow +
            vr_TmpResult.p4asgs.qty_asg_tomorrow;
          
          vr_TmpResult.totals.qty_asg_d2 :=
            vr_TmpResult.p1asgs.qty_asg_d2 +
            vr_TmpResult.p2asgs.qty_asg_d2 +
            vr_TmpResult.p3asgs.qty_asg_d2 +
            vr_TmpResult.p4asgs.qty_asg_d2;
          
          vr_TmpResult.totals.qty_asg_d3 :=
            vr_TmpResult.p1asgs.qty_asg_d3 +
            vr_TmpResult.p2asgs.qty_asg_d3 +
            vr_TmpResult.p3asgs.qty_asg_d3 +
            vr_TmpResult.p4asgs.qty_asg_d3;
          
          vr_TmpResult.totals.qty_asg_d4 :=
            vr_TmpResult.p1asgs.qty_asg_d4 +
            vr_TmpResult.p2asgs.qty_asg_d4 +
            vr_TmpResult.p3asgs.qty_asg_d4 +
            vr_TmpResult.p4asgs.qty_asg_d4;
          
          vr_TmpResult.totals.qty_asg_d5 :=
            vr_TmpResult.p1asgs.qty_asg_d5 +
            vr_TmpResult.p2asgs.qty_asg_d5 +
            vr_TmpResult.p3asgs.qty_asg_d5 +
            vr_TmpResult.p4asgs.qty_asg_d5;
          
          vr_TmpResult.totals.qty_asg_d6 :=
            vr_TmpResult.p1asgs.qty_asg_d6 +
            vr_TmpResult.p2asgs.qty_asg_d6 +
            vr_TmpResult.p3asgs.qty_asg_d6 +
            vr_TmpResult.p4asgs.qty_asg_d6;
          
          vr_TmpResult.totals.qty_asg_d7 :=
            vr_TmpResult.p1asgs.qty_asg_d7 +
            vr_TmpResult.p2asgs.qty_asg_d7 +
            vr_TmpResult.p3asgs.qty_asg_d7 +
            vr_TmpResult.p4asgs.qty_asg_d7;
          
          vr_TmpResult.totals.qty_asg_d8 :=
            vr_TmpResult.p1asgs.qty_asg_d8 +
            vr_TmpResult.p2asgs.qty_asg_d8 +
            vr_TmpResult.p3asgs.qty_asg_d8 +
            vr_TmpResult.p4asgs.qty_asg_d8;
          
          vr_TmpResult.totals.qty_asg_d9 :=
            vr_TmpResult.p1asgs.qty_asg_d9 +
            vr_TmpResult.p2asgs.qty_asg_d9 +
            vr_TmpResult.p3asgs.qty_asg_d9 +
            vr_TmpResult.p4asgs.qty_asg_d9;
          
          vr_TmpResult.totals.qty_asg_d10 :=
            vr_TmpResult.p1asgs.qty_asg_d10 +
            vr_TmpResult.p2asgs.qty_asg_d10 +
            vr_TmpResult.p3asgs.qty_asg_d10 +
            vr_TmpResult.p4asgs.qty_asg_d10;
          
          vr_TmpResult.totals.qty_asg_future :=
            vr_TmpResult.p1asgs.qty_asg_future +
            vr_TmpResult.p2asgs.qty_asg_future +
            vr_TmpResult.p3asgs.qty_asg_future +
            vr_TmpResult.p4asgs.qty_asg_future;
          
          vr_TmpResult.totals.rating_asg_future :=
            vr_TmpResult.p1asgs.rating_asg_future +
            vr_TmpResult.p2asgs.rating_asg_future +
            vr_TmpResult.p3asgs.rating_asg_future +
            vr_TmpResult.p4asgs.rating_asg_future;
          
          vr_TmpResult.totals.qty_asg_overage :=
            vr_TmpResult.p1asgs.qty_asg_overage +
            vr_TmpResult.p2asgs.qty_asg_overage +
            vr_TmpResult.p3asgs.qty_asg_overage +
            vr_TmpResult.p4asgs.qty_asg_overage;
          
          IF vb_FoundBest = FALSE
          OR CurrentResultIsBetter(vr_BestResult,vr_TmpResult) = TRUE
          THEN
            vr_BestResult := vr_TmpResult;
            vb_FoundBest := TRUE;
          END IF;
        END LOOP; -- loop for each matrix available
        
        RETURN vr_BestResult;
      END; -- bestmtx_for_typedateqty
      
    BEGIN -- Large block of code
      
      vr_BlankLenAsg.qty_asg_dminus3 := 0;
      vr_BlankLenAsg.qty_asg_dminus2 := 0;
      vr_BlankLenAsg.qty_asg_dminus1 := 0;
      vr_BlankLenAsg.qty_asg_today := 0;
      vr_BlankLenAsg.qty_asg_tomorrow := 0;
      vr_BlankLenAsg.qty_asg_d2 := 0;
      vr_BlankLenAsg.qty_asg_d3 := 0;
      vr_BlankLenAsg.qty_asg_d4 := 0;
      vr_BlankLenAsg.qty_asg_d5 := 0;
      vr_BlankLenAsg.qty_asg_d6 := 0;
      vr_BlankLenAsg.qty_asg_d7 := 0;
      vr_BlankLenAsg.qty_asg_d8 := 0;
      vr_BlankLenAsg.qty_asg_d9 := 0;
      vr_BlankLenAsg.qty_asg_d10 := 0;
      vr_BlankLenAsg.qty_asg_future := 0;
      vr_BlankLenAsg.rating_asg_future := 0;
      vr_BlankLenAsg.qty_asg_overage := 0;
      
      vr_BlankResult.qtypcs := 0;
      vr_BlankResult.p1len := 0;
      vr_BlankResult.p1pun := 'S';
      vr_BlankResult.p1asgs := vr_BlankLenAsg;
      vr_BlankResult.p2len := 0;
      vr_BlankResult.p2pun := 'S';
      vr_BlankResult.p2asgs := vr_BlankLenAsg;
      vr_BlankResult.p3len := 0;
      vr_BlankResult.p3pun := 'S';
      vr_BlankResult.p3asgs := vr_BlankLenAsg;
      vr_BlankResult.p4len := 0;
      vr_BlankResult.p4pun := 'S';
      vr_BlankResult.p4asgs := vr_BlankLenAsg;
      vr_BlankResult.totals := vr_BlankLenAsg;
      
      ---
      -- Loop for each capacity/pocket-size available
      -- and select an optimal matrix for that capacity
      
      LOOP
        
        oBestUse.extend(1);
        oBestUse(oBestUse.count).thecapacity := vn_QtyBarsPerRun;
        
        IF oBestUse.count > 1
        THEN
          oBestUse(oBestUse.count).thecapacity :=
            oBestUse((oBestUse.count)-1).thecapacity + vn_QtyBarsPerRun;
        END IF;
        
        oBestUse(oBestUse.count).theresult := vr_BlankResult;
        
        oBestUse(oBestUse.count).theresult :=
                  bestmtx_for_typedateqty(oBestUse(oBestUse.count).thecapacity);
        
        IF oBestUse(oBestUse.count).thecapacity >= vn_MaxPocketCapacity
        THEN
          IF oBestUse(oBestUse.count).thecapacity > vn_MaxPocketCapacity
          THEN
            vc_OutputMessage :=
              'Internal Error 2071 - '||
              'Pocket Capacity is not a multiple of QtyPerRun';
            RETURN vc_OutputMessage;
          END IF;
          
          exit;
        END IF;
        
        IF oBestUse(oBestUse.count).thecapacity + vn_CurrentBarQtyInDate
              = vn_MaxBars
        THEN exit;
        END IF;
      END LOOP;
      
      ---
      -- Now pick a pocket using
      -- the capacity/matrix results we just got above
      
      LOOP
        DECLARE
          vn_ChosenIdx number;
          vn_ChosenPocketSize number;
        BEGIN
          vn_ChosenIdx := 1;
          
          FOR currctr IN 2 .. oBestUse.count -- loop for each qty/bestmtx
          LOOP
            IF CurrentResultIsBetter( oBestUse(vn_ChosenIdx).theresult,
                                      oBestUse(currctr).theresult)
            THEN vn_ChosenIdx := currctr;
            END IF;
          END LOOP; -- loop for each qty/bestmtx
          
          BEGIN
            SELECT storage_capacity INTO vn_ChosenPocketSize
            FROM
            (
              SELECT ROWNUM therownum, storage_capacity
              FROM
              (
                SELECT daypocket.storage_capacity
                FROM  reco_rstx_calday calday, reco_rstx_day_pocket daypocket
                WHERE daypocket.calday_id = calday.calday_id
                AND calday.thedate = pi_CurrentCutDate
                AND daypocket.parttype = pi_CurrentPartType
                AND NOT EXISTS (SELECT 1 FROM reco_rstx_day_pkt_bin subBins
                              WHERE subBins.day_pocket_id = daypocket.day_pocket_id)
                AND daypocket.storage_capacity >= oBestUse(vn_ChosenIdx).thecapacity
                ORDER BY daypocket.storage_capacity
              )
            )
            WHERE therownum = 1;
          EXCEPTION
            WHEN NO_DATA_FOUND
            THEN
              IF oBestUse.count > 1
              THEN
                FOR fwdctr IN vn_ChosenIdx+1 .. oBestUse.count
                LOOP
                  oBestUse(fwdctr-1).thecapacity := oBestUse(fwdctr).thecapacity;
                  oBestUse(fwdctr-1).theresult := oBestUse(fwdctr).theresult;
                END LOOP;
                
                ---- Note: DO NOT USE THE DELETE(N) METHOD IT WILL CAUSE
                --         PROBLEMS (I TESTED IT, AND THE COLL.COUNT WILL
                --         BE OFF.  USE TRIM INSTEAD
                oBestUse.trim(1);
                
                CONTINUE;
              END IF;
          END;
          
          apply_matrix_to_reqs(
            pi_CurrentPartType,
            pi_CurrentCutDate,
            oBestUse(vn_ChosenIdx).thecapacity,
            vn_ChosenPocketSize,
            oBestUse(vn_ChosenIdx).theresult.qtypcs,
            oBestUse(vn_ChosenIdx).theresult.p1len,
            oBestUse(vn_ChosenIdx).theresult.p1pun,
            oBestUse(vn_ChosenIdx).theresult.p2len,
            oBestUse(vn_ChosenIdx).theresult.p2pun,
            oBestUse(vn_ChosenIdx).theresult.p3len,
            oBestUse(vn_ChosenIdx).theresult.p3pun,
            oBestUse(vn_ChosenIdx).theresult.p4len,
            oBestUse(vn_ChosenIdx).theresult.p4pun);
          
          exit;
        END;
      END LOOP;
    END; -- Large block of code
    
    -- Loop again, and try to find another pocket to fill
    
  END LOOP; -- Loop to apply_matrix_to_reqs many times
  
  -----
  -- We have finished assiging pockets, but we may be under the
  -- "max bars" for the day.
  -- 
  -- This is okay, but then we cannot finish the day here.
  -- Since parttypes could be mixed into a single date, then we
  -- let the caller handle the case where the day is not full
  
  -----
  -- Done
  
  RETURN vc_OutputMessage;
END; -- assign_runs_for_daypart

--------------------------------------------------------------------------------
-- set_bin_labels
PROCEDURE set_bin_labels (pi_CurrentCutDate IN date,
                          pi_largerbars_near_machine IN varchar2)
IS
  vn_MaxPceSizeSmallMachine number := 14;
  
  TYPE coll_DayPocket IS TABLE OF reco_rstx_day_pocket%ROWTYPE;
  oDayPocket coll_DayPocket; -- Fetched, so don't initialize
  --oDayPktBin coll_DayPocket := coll_DayPocket(); -- Initialize since not fetched
  
  TYPE coll_DayPktBin IS TABLE OF reco_rstx_day_pkt_bin%ROWTYPE;
  oDayPktBin coll_DayPktBin; -- Fetched, so don't initialize
  --oDayPktBin coll_DayPktBin := coll_DayPktBin(); -- Initialize since not fetched
BEGIN -- set_bin_labels
  
  SELECT daypocket.*
  BULK COLLECT INTO oDayPocket
  FROM reco_rstx_calday calday, reco_rstx_day_pocket daypocket
  WHERE calday.calday_id = daypocket.calday_id
  AND calday.thedate = pi_CurrentCutDate;
  
  FOR daypocketctr IN 1 .. oDayPocket.count
  LOOP
    SELECT *
    BULK COLLECT INTO oDayPktBin
    FROM reco_rstx_day_pkt_bin
    WHERE day_pocket_id = oDayPocket(daypocketctr).day_pocket_id
    ORDER BY length_of_part;
    
    DECLARE
      vc_BinSuffix varchar2(3);
      
      vn_CurrBinPhysicalNum number;
    BEGIN
      vc_BinSuffix := '-B'||TO_CHAR(oDayPocket(daypocketctr).pocket_number);
      
      IF pi_largerbars_near_machine = 'N'
      THEN
        vn_CurrBinPhysicalNum := 60; -- CONTINUE HERE ADJBLE POCKET SIZE ???
        
        FOR daypktbinctr IN REVERSE 1 .. oDayPktBin.count
        LOOP
          IF oDayPktBin(daypktbinctr).length_of_part <= vn_MaxPceSizeSmallMachine
          THEN exit;
          END IF;
          
          oDayPktBin(daypktbinctr).last_machine_label :=
            TO_CHAR(vn_CurrBinPhysicalNum)||vc_BinSuffix;
          
          vn_CurrBinPhysicalNum :=
            vn_CurrBinPhysicalNum - oDayPktBin(daypktbinctr).length_used;
          
          oDayPktBin(daypktbinctr).first_machine_label :=
            TO_CHAR(vn_CurrBinPhysicalNum)||vc_BinSuffix;
          
          vn_CurrBinPhysicalNum := vn_CurrBinPhysicalNum - 2;
        END LOOP;
        
        vn_CurrBinPhysicalNum := 0;
        
        FOR daypktbinctr IN 1 .. oDayPktBin.count
        LOOP
          IF oDayPktBin(daypktbinctr).length_of_part > vn_MaxPceSizeSmallMachine
          THEN exit;
          END IF;
          
          oDayPktBin(daypktbinctr).first_machine_label :=
            TO_CHAR(vn_CurrBinPhysicalNum)||vc_BinSuffix;
          
          vn_CurrBinPhysicalNum :=
            vn_CurrBinPhysicalNum + oDayPktBin(daypktbinctr).length_used;
          
          oDayPktBin(daypktbinctr).last_machine_label :=
            TO_CHAR(vn_CurrBinPhysicalNum)||vc_BinSuffix;
          
          vn_CurrBinPhysicalNum := vn_CurrBinPhysicalNum + 2;
        END LOOP;
      ELSIF pi_largerbars_near_machine = 'Y'
      THEN
        vn_CurrBinPhysicalNum := 0;
        
        FOR daypktbinctr IN REVERSE 1 .. oDayPktBin.count
        LOOP
          oDayPktBin(daypktbinctr).first_machine_label :=
            TO_CHAR(vn_CurrBinPhysicalNum)||vc_BinSuffix;
          
          vn_CurrBinPhysicalNum :=
            vn_CurrBinPhysicalNum + oDayPktBin(daypktbinctr).length_used;
          
          oDayPktBin(daypktbinctr).last_machine_label :=
            TO_CHAR(vn_CurrBinPhysicalNum)||vc_BinSuffix;
          
          vn_CurrBinPhysicalNum := vn_CurrBinPhysicalNum + 2;
        END LOOP;
      END IF;
      
      FOR loopCtr IN 1 .. oDayPktBin.count
      LOOP
        UPDATE reco_rstx_day_pkt_bin
        set first_machine_label = oDayPktBin(loopCtr).first_machine_label,
            last_machine_label = oDayPktBin(loopCtr).last_machine_label
        WHERE day_pkt_bin_id = oDayPktBin(loopCtr).day_pkt_bin_id;
      END LOOP;
    END;
  END LOOP;
END; -- set_bin_labels

--------------------------------------------------------------------------------
-- setup_punch_requirements
-- 
-- Looks at SHIPPING for RSTX, figures out which punches are needed by which
-- days, then adds the information to reco_rstx_punreq table
-- 
-- It is possible to have an entry in reco_rstx_punreq that does not
-- have any required qty (e.g. qty_req_black is 0, qty_req_galv is 0 ...)
-- This happens whenever we satisfy a requirement without budgeting
-- a "New cutting need":
-- : when we convert existing PUNCHED piece in inventory (B -> G) to
--   fill a galv requirement
-- This way, the punreq table tracks any assumptions / conversions from
-- outside of the system.
-- 
-- We ignore any requirements where the part has inventory_item_id null
-- in the reco_rstx_originvqty table.
-- If the part has null inventory_item_id, then we ignore it
-- (the shipment's demand does not go into reco_rstx_punreq calcs)
-- 
-- PRE-CONDITIONS
-- : clear_existing_reqsandplans
-- : validate_and_count_inv should have completed successfully
--   (it should have returned 'DONE' message)
-- : The CUT SCHEDULE (for cutting 48/49 bars to nopunch)
--   should theoretically already have been done
-- : pi_first_date_of_reqs is the first date we start looking for shipments that
--   haven't been sent yet. It can be before sysdate if desired (to grab
--   shipments from yesterday etc...)
-- : pi_min_cut_allowed should reflect the minimum piece length we want
--   to consider. If a shipment has lengths less-than the minimum size, the
--   system will generate exception for that piece
-- : pi_max_cut_allowed should reflect the maximum piece length we want
--   to consider. If a shipment has lengths more-than the maximum size, the
--   system will generate exception for that piece
PROCEDURE setup_punch_requirements (pi_first_date_of_reqs IN date,
                                    pi_min_cut_allowed IN number,
                                    pi_max_cut_allowed IN number)
IS
  -- Intentional: Lumps black/galv version of things together
  -- 
  -- NOTE: We still need to track NoPunch requirements,
  --       because if we ever start shipping NoPunch then
  --       theoretically we should track the inventory degredation
  CURSOR cur_ShipmentDemand
  IS
    SELECT  DISTINCT TRUNC(rs.truck_date) thedate,
            roiq.numlength thelength,
            roiq.thetype thetype,
            roiq.thepunch thepunch,
            roiq.charlength charlength,
            CASE
            WHEN roiq.thepunch = 'N'
            THEN 1
            WHEN roiq.thepunch = 'D'
            THEN 2
            WHEN roiq.thepunch = 'S'
            THEN 3
            ELSE 4
            END sortord_punch
    FROM  reco_truck rs,
          reco_truckstop_parts rsp,
          reco_rstx_originvqty roiq
    WHERE   rs.truck_id = rsp.stop_truck_id
    AND     rsp.part_id = roiq.inventory_item_id
    AND     rs.truck_status IN ('A','H','B')
    AND     rsp.orig_subinventory_code IN ('RSTX')
    AND     NVL(rsp.quantity,0) > 0
    AND     rs.truck_date >= pi_first_date_of_reqs
    AND     roiq.numlength >= pi_min_cut_allowed
    AND     roiq.numlength <= pi_max_cut_allowed
    AND     roiq.inventory_item_id IS NOT NULL
    ORDER BY  roiq.numlength desc,  -- Always analyze longer before shorter
              roiq.thetype,         -- And always break-out length/type
              TRUNC(rs.truck_date), -- before the date consideration
              CASE
              WHEN roiq.thepunch = 'N'
              THEN 1
              WHEN roiq.thepunch = 'D'
              THEN 2
              WHEN roiq.thepunch = 'S'
              THEN 3
              ELSE 4
              END; -- sort order changed May-2013 DSM
  
  TYPE coll_ShipmentDemand IS TABLE OF cur_ShipmentDemand%ROWTYPE;
  oTheShipmentDemand coll_ShipmentDemand; -- Fetched, so don't initialize
  
  rec_CurrCalc reco_rstx_punreqcalc%ROWTYPE;
  
  vn_CurrentQtyRawStl number;
  vn_CurrentQtyNPB number;
  vn_CurrentQtyNPG number;
  vn_CurrentQtySPB number;
  vn_CurrentQtySPG number;
  vn_CurrentQtyDPB number;
  vn_CurrentQtyDPG number;
  
  vn_CurrBlackQtyThisRec number;
  vn_CurrGalvQtyThisRec number;
  
BEGIN -- setup_punch_requirements
  
  ---
  -- Gather all sorts of knowledge about the date/type/punch demand
  -- from shipping, and use the reco_rstx_punreqcalc table to store calcs
  ---
  
  DELETE FROM reco_rstx_punreqcalc;
  
  OPEN cur_ShipmentDemand;
  FETCH cur_ShipmentDemand BULK COLLECT INTO oTheShipmentDemand;
  CLOSE cur_ShipmentDemand;
  
  FOR collCtr IN 1 .. oTheShipmentDemand.count -- Oracle collections start at 1 ...
  LOOP
    
    ----------
    -- Basic data for reqcalc
    ----------
    
    rec_CurrCalc.thedate :=
      oTheShipmentDemand(collCtr).thedate;
    
    rec_CurrCalc.thelength :=
      oTheShipmentDemand(collCtr).thelength;
    
    rec_CurrCalc.thetype :=
      oTheShipmentDemand(collCtr).thetype;
    
    rec_CurrCalc.thepunch :=
      oTheShipmentDemand(collCtr).thepunch;
    
    ----------
    -- We track inventory per parttype/partlength, so initialize
    -- (and we track all 3 punches inventory together)
    ----------
    
    -- Reset if we are looking at a new partlength / parttype
    IF collCtr = 1
    OR oTheShipmentDemand(collCtr).thelength
          != oTheShipmentDemand(collCtr-1).thelength
    OR oTheShipmentDemand(collCtr).thetype
          != oTheShipmentDemand(collCtr-1).thetype
    THEN
      vn_CurrentQtyRawStl := 0;
      vn_CurrentQtyNPB := 0;
      vn_CurrentQtyNPG := 0;
      vn_CurrentQtySPB := 0;
      vn_CurrentQtySPG := 0;
      vn_CurrentQtyDPB := 0;
      vn_CurrentQtyDPG := 0;
      
      DECLARE
        vn_TotNU number;
        vn_TotSM number;
      BEGIN
        SELECT quantity INTO vn_TotNU
        FROM reco_rstx_originvqty
        WHERE category_set_id = nCSetR
        AND thepunch = 'NU'
        AND thetype = oTheShipmentDemand(collCtr).thetype
        AND thecoat = 'B'
        AND charlength = oTheShipmentDemand(collCtr).charlength;
        
        IF vn_TotNU < 0 -- Added FEB2013
        THEN vn_TotNU := 0; END IF;
        
        SELECT quantity INTO vn_TotSM
        FROM reco_rstx_originvqty
        WHERE category_set_id = nCSetR
        AND thepunch = 'SM'
        AND thetype = oTheShipmentDemand(collCtr).thetype
        AND thecoat = 'B'
        AND charlength = oTheShipmentDemand(collCtr).charlength;
        
        IF vn_TotSM < 0 -- Added FEB2013
        THEN vn_TotSM := 0; END IF;
        
        vn_CurrentQtyRawStl := vn_TotNU + vn_TotSM;
      END;
      
      SELECT  oiq.quantity
      INTO  vn_CurrentQtyNPB
      FROM  reco_rstx_originvqty oiq
      WHERE   oiq.thepunch = 'N'
      AND     oiq.thetype = oTheShipmentDemand(collCtr).thetype
      AND     oiq.thecoat = 'B'
      AND     oiq.charlength = oTheShipmentDemand(collCtr).charlength;
      
      IF vn_CurrentQtyNPB < 0 -- Added FEB2013
      THEN vn_CurrentQtyNPB := 0; END IF;
      
      vn_CurrentQtyNPG := 0;
      --  select  oiq.quantity
      --  into  vn_CurrQtyNPG
      --  from  reco_rstx_originvqty oiq
      --  where   oiq.thepunch = 'N'
      --  and     oiq.thetype = oTheShipmentDemand(collCtr).thetype
      --  and     oiq.thecoat = 'G'
      --  and     oiq.charlength = oTheShipmentDemand(collCtr).charlength;
      --  
      --  if vn_CurrentQtyNPG < 0 -- Added FEB2013
      --  then vn_CurrentQtyNPG := 0; end if;
      
      SELECT  oiq.quantity
      INTO  vn_CurrentQtySPB
      FROM  reco_rstx_originvqty oiq
      WHERE   oiq.thepunch = 'S'
      AND     oiq.thetype = oTheShipmentDemand(collCtr).thetype
      AND     oiq.thecoat = 'B'
      AND     oiq.charlength = oTheShipmentDemand(collCtr).charlength;
      
      IF vn_CurrentQtySPB < 0 -- Added FEB2013
      THEN vn_CurrentQtySPB := 0; END IF;
      
      SELECT  oiq.quantity
      INTO  vn_CurrentQtySPG
      FROM  reco_rstx_originvqty oiq
      WHERE   oiq.thepunch = 'S'
      AND     oiq.thetype = oTheShipmentDemand(collCtr).thetype
      AND     oiq.thecoat = 'G'
      AND     oiq.charlength = oTheShipmentDemand(collCtr).charlength;
      
      IF vn_CurrentQtySPG < 0 -- Added FEB2013
      THEN vn_CurrentQtySPG := 0; END IF;
      
      SELECT  oiq.quantity
      INTO  vn_CurrentQtyDPB
      FROM  reco_rstx_originvqty oiq
      WHERE   oiq.thepunch = 'D'
      AND     oiq.thetype = oTheShipmentDemand(collCtr).thetype
      AND     oiq.thecoat = 'B'
      AND     oiq.charlength = oTheShipmentDemand(collCtr).charlength;
      
      IF vn_CurrentQtyDPB < 0 -- Added FEB2013
      THEN vn_CurrentQtyDPB := 0; END IF;
      
      SELECT  oiq.quantity
      INTO  vn_CurrentQtyDPG
      FROM  reco_rstx_originvqty oiq
      WHERE   oiq.thepunch = 'D'
      AND     oiq.thetype = oTheShipmentDemand(collCtr).thetype
      AND     oiq.thecoat = 'G'
      AND     oiq.charlength = oTheShipmentDemand(collCtr).charlength;
      
      IF vn_CurrentQtyDPG < 0 -- Added FEB2013
      THEN vn_CurrentQtyDPG := 0; END IF;
      
    END IF; -- Reset if we are looking at a new partlength / parttype
    
    ----------
    -- Because we are breaking out the N/S/D tracking in some ways,
    -- then it is easiest to include a SINGLE IF STATEMENT here
    -- instead of repeating the same IF N IF S IF D ...
    ----------
    
    vn_CurrBlackQtyThisRec := 0;
    vn_CurrGalvQtyThisRec := 0;
    
    IF oTheShipmentDemand(collCtr).thepunch = 'N'
    THEN
      vn_CurrBlackQtyThisRec := vn_CurrentQtyNPB;
      vn_CurrGalvQtyThisRec := vn_CurrentQtyNPG;
    ELSIF oTheShipmentDemand(collCtr).thepunch = 'S'
    THEN
      vn_CurrBlackQtyThisRec := vn_CurrentQtySPB;
      vn_CurrGalvQtyThisRec := vn_CurrentQtySPG;
    ELSIF oTheShipmentDemand(collCtr).thepunch = 'D'
    THEN
      vn_CurrBlackQtyThisRec := vn_CurrentQtyDPB;
      vn_CurrGalvQtyThisRec := vn_CurrentQtyDPG;
    END IF;
    
    ----------
    -- Set start of day inventory for this parttype/partlength
    ----------
    
    rec_CurrCalc.rawsteel_start_inv := vn_CurrentQtyRawStl;
    
    rec_CurrCalc.black_daystart_inv := vn_CurrBlackQtyThisRec;
    
    rec_CurrCalc.galv_daystart_inv := vn_CurrGalvQtyThisRec;
    
    ----------
    -- Set day demand for this date for this parttype/partlength
    ----------
    
    SELECT  SUM(rsp.quantity)
    INTO  rec_CurrCalc.black_daydemand
    FROM  reco_truckstop_parts rsp,
          reco_truck rs,
          reco_rstx_originvqty roiq
    WHERE rs.truck_id = rsp.stop_truck_id
    AND rsp.orig_subinventory_code IN ('RSTX')
    AND rs.truck_status IN ('A','H','B')
    AND rs.truck_date
            >= TRUNC(oTheShipmentDemand(collCtr).thedate)
    AND rs.truck_date
            < TRUNC(oTheShipmentDemand(collCtr).thedate) + 1
    AND rsp.part_id = roiq.inventory_item_id
    AND roiq.segment1 LIKE
                      oTheShipmentDemand(collCtr).thepunch||
                      oTheShipmentDemand(collCtr).thetype||
                      'B'||
                      oTheShipmentDemand(collCtr).charlength;
    
    rec_CurrCalc.black_daydemand := NVL(rec_CurrCalc.black_daydemand,0);
    
    SELECT  SUM(rsp.quantity)
    INTO  rec_CurrCalc.galv_daydemand
    FROM  reco_truckstop_parts rsp,
          reco_truck rs,
          reco_rstx_originvqty roiq
    WHERE rs.truck_id = rsp.stop_truck_id
    AND rsp.orig_subinventory_code IN ('RSTX')
    AND rs.truck_status IN ('A','H','B')
    AND rs.truck_date
            >= TRUNC(oTheShipmentDemand(collCtr).thedate)
    AND rs.truck_date
            < TRUNC(oTheShipmentDemand(collCtr).thedate) + 1
    AND rsp.part_id = roiq.inventory_item_id
    AND roiq.segment1 LIKE
                      oTheShipmentDemand(collCtr).thepunch||
                      oTheShipmentDemand(collCtr).thetype||
                      'G'||
                      oTheShipmentDemand(collCtr).charlength;
    
    rec_CurrCalc.galv_daydemand := NVL(rec_CurrCalc.galv_daydemand,0);
    
    ----------
    -- Budget all new production.
    -- Ignore Black-to-Galvanizing conversion for now
    ----------
    
    IF vn_CurrGalvQtyThisRec >= rec_CurrCalc.galv_daydemand
    THEN
      rec_CurrCalc.galv_use_newpun := 0;
      vn_CurrGalvQtyThisRec :=
        vn_CurrGalvQtyThisRec - rec_CurrCalc.galv_daydemand;
    ELSIF vn_CurrGalvQtyThisRec < rec_CurrCalc.galv_daydemand
    THEN
      rec_CurrCalc.galv_use_newpun :=
        rec_CurrCalc.galv_daydemand - vn_CurrGalvQtyThisRec;
      vn_CurrGalvQtyThisRec := 0;
    END IF;
    
    IF vn_CurrBlackQtyThisRec >= rec_CurrCalc.black_daydemand
    THEN
      rec_CurrCalc.black_use_newpun := 0;
      vn_CurrBlackQtyThisRec :=
        vn_CurrBlackQtyThisRec - rec_CurrCalc.black_daydemand;
    ELSIF vn_CurrBlackQtyThisRec < rec_CurrCalc.black_daydemand
    THEN
      rec_CurrCalc.black_use_newpun :=
        rec_CurrCalc.black_daydemand - vn_CurrBlackQtyThisRec;
      vn_CurrBlackQtyThisRec := 0;
    END IF;
    
    ----------
    -- Apply Black-to-Galvanized conversion for galvanzied demand
    ----------
    
    rec_CurrCalc.galv_convfromblk := 0;
    
    IF rec_CurrCalc.galv_use_newpun <= vn_CurrBlackQtyThisRec
    THEN
      rec_CurrCalc.galv_convfromblk := rec_CurrCalc.galv_use_newpun;
      vn_CurrBlackQtyThisRec :=
        vn_CurrBlackQtyThisRec - rec_CurrCalc.galv_use_newpun;
      rec_CurrCalc.galv_use_newpun := 0;
    ELSIF rec_CurrCalc.galv_use_newpun > vn_CurrBlackQtyThisRec
    THEN
      rec_CurrCalc.galv_convfromblk := vn_CurrBlackQtyThisRec;
      rec_CurrCalc.galv_use_newpun :=
        rec_CurrCalc.galv_use_newpun - vn_CurrBlackQtyThisRec;
      vn_CurrBlackQtyThisRec := 0;
    END IF;
    
    ----------
    -- Now we know everthing for this specific punch on
    -- this day/length/type.
    -- 
    -- We are done preparing the one record for reco_rstx_punreqcalc,
    -- but don't forget to update our running inventory totals
    ----------
    
    IF oTheShipmentDemand(collCtr).thepunch = 'N'
    THEN
      vn_CurrentQtyNPB := vn_CurrBlackQtyThisRec;
      vn_CurrentQtyNPG := vn_CurrGalvQtyThisRec;
    ELSIF oTheShipmentDemand(collCtr).thepunch = 'S'
    THEN
      vn_CurrentQtySPB := vn_CurrBlackQtyThisRec;
      vn_CurrentQtySPG := vn_CurrGalvQtyThisRec;
    ELSIF oTheShipmentDemand(collCtr).thepunch = 'D'
    THEN
      vn_CurrentQtyDPB := vn_CurrBlackQtyThisRec;
      vn_CurrentQtyDPG := vn_CurrGalvQtyThisRec;
    END IF;
    
    INSERT INTO reco_rstx_punreqcalc
      (thedate,thelength,thetype,thepunch,
        rawsteel_start_inv,
        black_daystart_inv,black_daydemand,black_use_newpun,
        galv_daystart_inv,galv_daydemand,
        galv_use_newpun,galv_convfromblk)
    VALUES
      ( rec_CurrCalc.thedate,
        rec_CurrCalc.thelength,
        rec_CurrCalc.thetype,
        rec_CurrCalc.thepunch,
        rec_CurrCalc.rawsteel_start_inv,
        rec_CurrCalc.black_daystart_inv,
        rec_CurrCalc.black_daydemand,
        rec_CurrCalc.black_use_newpun,
        rec_CurrCalc.galv_daystart_inv,
        rec_CurrCalc.galv_daydemand,
        rec_CurrCalc.galv_use_newpun,
        rec_CurrCalc.galv_convfromblk);
    
  END LOOP;
  
  DELETE FROM reco_rstx_punreq;
  
  INSERT INTO reco_rstx_punreq
    (punreq_id,
      reqdate,reqlength,reqtype,reqpunch,
      qty_req_black, qty_req_galv,
      qty_done_convbtog,
      tot_qty_req,
      creation_date,created_by,last_update_date,
      last_updated_by,last_update_login)
  SELECT  reco_rstx_punreq_seq.nextval,
          thedate,thelength,thetype,thepunch,
          black_use_newpun,galv_use_newpun,
          galv_convfromblk,
          ( black_use_newpun + galv_use_newpun ),
          SYSDATE,-1,SYSDATE,-1,-1
  FROM
    (
      SELECT  thedate,thelength,thetype,thepunch,
              rawsteel_start_inv,
              black_daystart_inv,black_daydemand,
              black_use_newpun,
              galv_daystart_inv,galv_daydemand,
              galv_use_newpun,galv_convfromblk,
              CASE
              WHEN thepunch = 'N'
              THEN 1
              WHEN thepunch = 'D'
              THEN 2
              WHEN thepunch = 'S'
              THEN 3
              ELSE 4
              END thesortord
      FROM reco_rstx_punreqcalc
      WHERE   thepunch != 'N'
      AND     (
                black_use_newpun > 0 OR
                galv_use_newpun > 0 OR
                galv_convfromblk > 0
              )
      ORDER BY  TRUNC(thedate),
                thelength desc, -- Always analyze longer before shorter
                thetype,
                CASE
                WHEN thepunch = 'N'
                THEN 1
                WHEN thepunch = 'D'
                THEN 2
                WHEN thepunch = 'S'
                THEN 3
                ELSE 4
                END
    );
  
END;  -- setup_punch_requirements

--------------------------------------------------------------------------------
-- assign_punch_runs
-- 
-- These items are given: CutDate/Length-Range to consider
-- 
-- We grab each empty pocket available on the date,
-- and then assign some cut matrix to each of those pockets
-- 
-- PRE-CONDITIONS
-- : setup_punch_requirements must have completed without error
-- : pi_CurrentCutDate should realistically be a working day in
--   the reco_rstx_calday table (have is_production_allowed set to Y)
-- 
-- POST-CONDITIONS
-- : Populate these tables:
--   - reco_rstx_punrun
--   - reco_rstx_punasg
-- : This method uses a loop to call apply_punasg_to_reqs many times.
--   The goal is to apply lots of punch/quantity to fill all requirements
--   : There are no Requirements left
--   -or-
--   : We have reached the vn_MaxQtyPerDayPunch
-- : returns 'DONE' when successful, or an error message when problems occur
FUNCTION assign_punch_runs(pi_CurrentCutDate IN date)
RETURN varchar2
IS
  
  vn_MaxBars number;
  
  vn_CurrentBarQtyInDate number;
  
  vc_OutputMessage varchar2(1000);
  
BEGIN -- assign_punch_runs
  
  -----
  -- Default output to an error
  -- (Unless the process exits at specific places, then we have an error)
  vc_OutputMessage :=
    'Error: Unkn assign error in assign_punch_runs. Contact MIS';
  
  -----
  -- We are about to start a loop
  -- LOOP
  --   If NoMoreRequirements
  --   or MaxBarsPerDayIsReached
  --   then exitOK;
  --   end If;
  --   
  --   Fill a new run with punch assignments
  -- END LOOP
  
  -- This loop is over 2,200 lines long !!
  
  -----
  -- Loop to apply_punasg_to_reqs many times
  
  LOOP -- Loop to apply_punasg_to_reqs many times
    
    -----
    -- Validate: Are there any requirements left?
    -- 
    -- If NO, then exit;
    
    -- Remember, we only consider requirements for current parameters:
    -- :pi_CurrentPartType
    -- :pi_MinimumPceSize
    -- :pi_MaximumPceSize
    -- 
    -- Note: The values in reco_rstx_punreq already considered the
    --       pi_MinimumPceSize and pi_MaximumPceSize handling
    
    DECLARE
      vc_Temp number;
    BEGIN
      SELECT 1 INTO vc_Temp
      FROM
            (
              SELECT  SUM(punreq.tot_qty_req) totQty
              FROM  reco_rstx_punreq punreq
            ) subQReq,
            (
              SELECT  SUM(punasg.qty_asg_black + punasg.qty_asg_galv) totQty
              FROM  reco_rstx_punasg punasg
            ) subQAsg
      WHERE subQReq.totQty > NVL(subQAsg.totQty,0);
    EXCEPTION
      WHEN NO_DATA_FOUND
      THEN
        vc_OutputMessage := 'DONE';
        exit;
      WHEN TOO_MANY_ROWS
      THEN
        NULL;
      WHEN others
      THEN
        vc_OutputMessage := 'Intenal Error at requirements review';
        exit;
    END;
    
    -----
    -- Determine the maximum number of bars in this date
    vn_MaxBars := vn_MaxQtyPerDayPunch;
    
    -----
    -- If we have reached our daily limit, then of course we are done,
    -- regardless of how many pockets were filled
    
    SELECT SUM(punrun.qty_bars_processed) INTO vn_CurrentBarQtyInDate
    FROM  reco_rstx_calday calday,
          reco_rstx_punrun punrun
    WHERE   pi_CurrentCutDate = calday.thedate
    AND     calday.calday_id = punrun.calday_id;
    
    IF vn_CurrentBarQtyInDate IS NULL
    THEN vn_CurrentBarQtyInDate := 0;
    END IF;
    
    IF vn_CurrentBarQtyInDate >= vn_MaxBars
    THEN
      vc_OutputMessage := 'DONE';
      IF vn_CurrentBarQtyInDate > vn_MaxBars
      THEN vc_OutputMessage := 'Internal Error 2072 - Excessive punching in day';
      END IF;
      
      exit;
    END IF;
    
    -----
    -- Pick the earliest punch/length/type that is needed
    -- then,
    -- Determine the number of runs
    -- then,
    -- Apply the run to requirements
    
    DECLARE
      TYPE typ_SelectedPunchReq IS record (
              therownum number,
              reqlength reco_rstx_punreq.reqlength%TYPE,
              reqtype reco_rstx_punreq.reqtype%TYPE,
              reqpunch reco_rstx_punreq.reqpunch%TYPE,
              reqdate reco_rstx_punreq.reqdate%TYPE,
              qtyRemain number);
      
      rec_SelectedPunchReq typ_SelectedPunchReq;
      
      vn_QtyBarsToRun number;
      
      vn_ChosenCalDayId number;
      vn_RunNumber number;
      
      vr_punrun reco_rstx_punrun%ROWTYPE;
    BEGIN
      
      -- Pick the earliest punch/length/type that is needed
      
      SELECT *
      INTO rec_SelectedPunchReq
      FROM
      (
        SELECT  ROWNUM therownum,
                reqlength,reqtype,reqpunch,reqdate,qtyRemain
        FROM
        (
          SELECT  punreq_id,reqlength,reqtype,reqpunch,reqdate,qtyRemain,
                  CASE
                  WHEN reqpunch = 'D' THEN 1
                  WHEN reqpunch = 'S' THEN 2
                  ELSE 3
                  END sortord_punch
          FROM  (
                  SELECT  subItemR.punreq_id,
                          subItemR.reqlength,
                          subItemR.reqtype,
                          subItemR.reqpunch,
                          subItemR.reqdate,
                          subItemR.tot_qty_req
                                  - NVL(subItemA.totQty,0) qtyRemain
                  FROM  (
                          SELECT  punreq.punreq_id,
                                  punreq.reqlength,
                                  punreq.reqtype,
                                  punreq.reqpunch,
                                  punreq.reqdate,
                                  punreq.tot_qty_req
                          FROM  reco_rstx_punreq punreq
                        ) subItemR,
                        (
                          SELECT  punreq.punreq_id,
                                  punreq.reqlength,
                                  punreq.reqtype,
                                  punreq.reqpunch,
                                  punreq.reqdate,
                                  SUM(punasg.qty_asg_black
                                          + punasg.qty_asg_galv) totQty
                          FROM  reco_rstx_punreq punreq,
                                reco_rstx_punasg punasg
                          WHERE   punreq.punreq_id = punasg.punreq_id
                          GROUP BY  punreq.punreq_id,
                                    punreq.reqlength,
                                    punreq.reqtype,
                                    punreq.reqpunch,
                                    punreq.reqdate
                        ) subItemA
                  WHERE subItemR.punreq_id = subItemA.punreq_id (+)
                )
          WHERE   qtyRemain > 0
          ORDER BY  reqdate,
                    reqtype,
                    CASE
                    WHEN reqpunch = 'D'
                    THEN 1
                    WHEN reqpunch = 'S'
                    THEN 2
                    ELSE 3
                    END,
                    reqlength desc  -- Always analyze longer before shorter
        )
      )
      WHERE therownum = 1;
      
      -- Determine the number of runs
      
      vn_QtyBarsToRun :=
        TRUNC(rec_SelectedPunchReq.qtyRemain / vn_PunchReportRounding)
        *
        vn_PunchReportRounding;
      
      IF MOD(rec_SelectedPunchReq.qtyRemain, vn_PunchReportRounding) != 0
      THEN vn_QtyBarsToRun := vn_QtyBarsToRun + vn_PunchReportRounding;
      END IF;
      
      IF vn_QtyBarsToRun > vn_MaxBars - vn_CurrentBarQtyInDate
      THEN
        vn_QtyBarsToRun := vn_MaxBars - vn_CurrentBarQtyInDate;
      END IF;
      
      IF vn_QtyBarsToRun = 0
      THEN
        vc_OutputMessage := 'Internal Error 2073 - Decided to punch 0 bars.';
        exit;
      END IF;
      
      -- Apply the run to requirements
      
      SELECT calday_id INTO vn_ChosenCalDayId
      FROM reco_rstx_calday WHERE thedate = pi_CurrentCutDate;
      
      SELECT MAX(run_number) INTO vn_RunNumber FROM reco_rstx_punrun;
      
      IF vn_RunNumber IS NULL THEN vn_RunNumber := 1;
      ELSIF vn_RunNumber IS NOT NULL THEN vn_RunNumber := vn_RunNumber + 1;
      END IF;
      
      SELECT reco_rstx_punrun_seq.nextval
      INTO vr_punrun.punrun_id
      FROM dual;
      
      vr_punrun.calday_id := vn_ChosenCalDayId;
      
      vr_punrun.run_number := vn_RunNumber;
      
      vr_punrun.qty_bars_processed := vn_QtyBarsToRun;
      
      INSERT INTO reco_rstx_punrun
        (punrun_id,calday_id,run_number,qty_bars_processed,
          last_update_date,last_updated_by,last_update_login,
          creation_date,created_by)
      VALUES
        (vr_punrun.punrun_id,vr_punrun.calday_id,
          vr_punrun.run_number,vr_punrun.qty_bars_processed,
          SYSDATE,-1,-1,SYSDATE,-1);
      
      DECLARE
        vn_CurrApplyQty number;
        
        CURSOR cur_Remaining
        IS
          SELECT  reqQ.punreq_id,
                  reqQ.reqdate,
                  (reqQ.qty_req_black-NVL(asgQ.totasg_b,0)) qty_remain_black,
                  (reqQ.qty_req_galv-NVL(asgQ.totasg_g,0)) qty_remain_galv
          FROM  (
                  SELECT  punreq.punreq_id,
                          punreq.reqdate,
                          punreq.qty_req_black,
                          punreq.qty_req_galv
                  FROM  reco_rstx_punreq punreq
                  WHERE   punreq.reqlength = rec_SelectedPunchReq.reqlength
                  AND     punreq.reqtype = rec_SelectedPunchReq.reqtype
                  AND     punreq.reqpunch = rec_SelectedPunchReq.reqpunch
                ) reqQ,
                (
                  SELECT  punreq.punreq_id,
                          SUM(punasg.qty_asg_black) totasg_b,
                          SUM(punasg.qty_asg_galv) totasg_g
                  FROM  reco_rstx_punreq punreq,
                        reco_rstx_punasg punasg
                  WHERE   punreq.punreq_id = punasg.punreq_id
                  AND     punreq.reqlength = rec_SelectedPunchReq.reqlength
                  AND     punreq.reqtype = rec_SelectedPunchReq.reqtype
                  AND     punreq.reqpunch = rec_SelectedPunchReq.reqpunch
                  GROUP BY  punreq.punreq_id
                ) asgQ
          WHERE   reqQ.punreq_id = asgQ.punreq_id (+)
          AND     ( reqQ.qty_req_black > NVL(asgQ.totasg_b,0) OR
                    reqQ.qty_req_galv > NVL(asgQ.totasg_g,0))
          ORDER BY  reqQ.reqdate;
          
        TYPE coll_Remaining IS TABLE OF cur_Remaining%ROWTYPE;
        
        oTheRemaining coll_Remaining; -- Fetched, so don't initialize
        --oTheRemaining coll_Remaining := coll_Remaining();
                                        -- Initialize since not fetched
        
        vr_punasg reco_rstx_punasg%ROWTYPE;
      BEGIN
        vn_CurrApplyQty := vr_punrun.qty_bars_processed;
        
        OPEN cur_Remaining;
        FETCH cur_Remaining BULK COLLECT INTO oTheRemaining;
        CLOSE cur_Remaining;
        
        FOR nCtrRemaining IN 1 .. oTheRemaining.count
        LOOP
          SELECT reco_rstx_punasg_seq.nextval
          INTO vr_punasg.punasg_id FROM dual;
          
          vr_punasg.punrun_id := vr_punrun.punrun_id;
          
          vr_punasg.punreq_id := oTheRemaining(nCtrRemaining).punreq_id;
          
          vr_punasg.qty_asg_galv := vn_CurrApplyQty;
          IF vr_punasg.qty_asg_galv
                    > oTheRemaining(nCtrRemaining).qty_remain_galv
          THEN
            vr_punasg.qty_asg_galv :=
                oTheRemaining(nCtrRemaining).qty_remain_galv;
          END IF;
          vn_CurrApplyQty := vn_CurrApplyQty - vr_punasg.qty_asg_galv;
          
          vr_punasg.qty_asg_black := vn_CurrApplyQty;
          IF vr_punasg.qty_asg_black
                    > oTheRemaining(nCtrRemaining).qty_remain_black
          THEN
            vr_punasg.qty_asg_black :=
                oTheRemaining(nCtrRemaining).qty_remain_black;
          END IF;
          vn_CurrApplyQty := vn_CurrApplyQty - vr_punasg.qty_asg_black;
          
          INSERT INTO reco_rstx_punasg
            (punasg_id,
              punrun_id,punreq_id,
              qty_asg_black,qty_asg_galv,
              last_update_date,last_updated_by,last_update_login,
              creation_date,created_by)
          VALUES
            (vr_punasg.punasg_id,
              vr_punasg.punrun_id,vr_punasg.punreq_id,
              vr_punasg.qty_asg_black,vr_punasg.qty_asg_galv,
              SYSDATE,-1,-1,SYSDATE,-1);
          
          IF vn_CurrApplyQty = 0
          THEN exit;
          END IF;
        END LOOP;
        
        IF vn_CurrApplyQty > 0
        THEN
          INSERT INTO reco_rstx_punovg
            (punovg_id,punrun_id,overage_qty,last_update_date,
              last_updated_by,last_update_login,creation_date,created_by)
          SELECT reco_rstx_punovg_seq.nextval,vr_punrun.punrun_id,
            vn_CurrApplyQty,SYSDATE,-1,-1,SYSDATE,-1
          FROM dual;
        END IF;
      END;
    END;
    
    -- Loop again, and try to find punch requirement to fill
    
  END LOOP; -- Loop to apply_punasg_to_reqs many times
  
  -----
  -- We have finished assiging runs,
  -- but we may be under the "max bars" for the day.
  -- 
  -- This is okay, but then we cannot finish the day here.
  -- Since parttypes could be mixed into a single date, then we
  -- let the caller handle the case where the day is not full
  
  -----
  -- Done
  
  RETURN vc_OutputMessage;
END; -- assign_punch_runs

--------------------------------------------------------------------------------
-- setup_galv_requirements
-- 
-- All the cutting is done, so now we do basic punch / galv planning
-- 
-- Punching/Galv is MUCH SIMPLER than the cutting process,
-- because we don't have to worry about any cut matixes or pocket selection.
-- 
-- We don't even assume that the fresh cuts are inventory. We ignore the cutsch
-- entirely when doing punch/galv "scheduling"
-- 
-- We ignore any requirements where the part has inventory_item_id null
-- in the reco_rstx_originvqty table.
-- If the part has null inventory_item_id, then we do not consider the
-- requirements (the shipment does not go into reco_rstx_punreq calcs)
-- 
-- PRE-CONDITIONS
-- : clear_existing_reqsandplans
-- : validate_and_count_inv should have completed successfully
--   (it should have returned 'DONE' message)
-- : pi_first_date_of_reqs is the first date we start looking for shipments that
--   haven't been sent yet. It can be before sysdate if desired (to grab
--   shipments from yesterday etc...)
-- : pi_min_cut_allowed should reflect the minimum piece length we want
--   to consider. If a shipment has lengths less-than the minimum size, the
--   system will generate exception for that piece
-- : pi_max_cut_allowed should reflect the maximum piece length we want
--   to consider. If a shipment has lengths more-than the maximum size, the
--   system will generate exception for that piece
PROCEDURE setup_galv_requirements (pi_first_date_of_reqs IN date,
                                    pi_min_cut_allowed IN number,
                                    pi_max_cut_allowed IN number)
IS
  vc_TmpLenString varchar2(2);
BEGIN -- setup_galv_requirements
  
  ---
  -- Gather all sorts of knowledge about the date/strip demand
  -- from shipping, and use the reco_rstx_galvreqcalc table to store calcs
  ---
  
  DECLARE
    -- Intentional: Lumps black/galv version of things together
    CURSOR cur_LengthDemandDates
    IS
      SELECT  DISTINCT -- remove multiple-shipments per day
              TRUNC(rs.truck_date) thedate,
              roiq.numlength thelength,
              roiq.thetype thetype
      FROM  reco_truck rs,
            reco_truckstop_parts rsp,
            reco_rstx_originvqty roiq
      WHERE   rs.truck_id = rsp.stop_truck_id
      AND     rsp.part_id = roiq.inventory_item_id
      AND     rs.truck_status IN ('A','H','B')
      AND     rsp.orig_subinventory_code IN ('RSTX')
      AND     NVL(rsp.quantity,0) > 0
      AND     rs.truck_date >= pi_first_date_of_reqs
      AND     roiq.numlength >= pi_min_cut_allowed
      AND     roiq.numlength <= pi_max_cut_allowed
      AND     roiq.inventory_item_id IS NOT NULL
      AND     ( roiq.thepunch = 'S' OR roiq.thepunch = 'D' )
      AND     roiq.thecoat = 'G'
      ORDER BY  roiq.numlength desc, -- Always analyze longer before shorter
                TRUNC(rs.truck_date),
                roiq.thetype; -- sort order changed Dec-2012 DSM
    
    TYPE coll_LengthDemandDates IS TABLE OF cur_LengthDemandDates%ROWTYPE;
    oTheLengthDemandDates coll_LengthDemandDates; -- Fetched, so don't initialize
    
    rec_CurrCalc reco_rstx_galvreqcalc%ROWTYPE;
    
    vn_CurrQtyRawStl number;
    vn_CurrQtyNPBAvail number;
    --vn_CurrQtyNPGAvail number;
    vn_CurrQtySPB number;
    vn_CurrQtySPG number;
    vn_CurrQtyDPB number;
    vn_CurrQtyDPG number;
    
  BEGIN
    OPEN cur_LengthDemandDates;
    FETCH cur_LengthDemandDates BULK COLLECT INTO oTheLengthDemandDates;
    CLOSE cur_LengthDemandDates;
    
    FOR vn_TmpCurrCtr IN 1 .. oTheLengthDemandDates.count -- Oracle collections start at 1 ...
    LOOP
      
      ----------
      -- Basic data for reqcalc
      ----------
      
      rec_CurrCalc.thedate :=
        oTheLengthDemandDates(vn_TmpCurrCtr).thedate;
      
      rec_CurrCalc.thelength :=
        oTheLengthDemandDates(vn_TmpCurrCtr).thelength;
      
      rec_CurrCalc.thetype :=
        oTheLengthDemandDates(vn_TmpCurrCtr).theType;
      
      ----------
      -- Length is a number, but partname length is a string
      ----------
      
      vc_TmpLenString :=
        TO_CHAR(oTheLengthDemandDates(vn_TmpCurrCtr).thelength);
      IF oTheLengthDemandDates(vn_TmpCurrCtr).thelength < 10
      THEN
        vc_TmpLenString := '0'||
          TO_CHAR(oTheLengthDemandDates(vn_TmpCurrCtr).thelength);
      END IF;
      
      ----------
      -- We track inventory per parttype/partlength, so initialize
      ----------
      
      -- Reset if we are looking at a new partlength / parttype
      IF vn_TmpCurrCtr = 1
      OR oTheLengthDemandDates(vn_TmpCurrCtr).thelength
            != oTheLengthDemandDates(vn_TmpCurrCtr-1).thelength
      OR oTheLengthDemandDates(vn_TmpCurrCtr).thetype
            != oTheLengthDemandDates(vn_TmpCurrCtr-1).thetype
      THEN
        vn_CurrQtyRawStl := 0;
        vn_CurrQtyNPBAvail := 0;
        --vn_CurrQtyNPGAvail := 0;
        vn_CurrQtySPB := 0;
        vn_CurrQtySPG := 0;
        vn_CurrQtyDPB := 0;
        vn_CurrQtyDPG := 0;
        
        DECLARE
          vn_TotNU number;
          vn_TotSM number;
        BEGIN
          --begin
            SELECT quantity INTO vn_TotNU
            FROM reco_rstx_originvqty
            WHERE category_set_id = nCSetR
            AND thepunch = 'NU'
            AND thetype = oTheLengthDemandDates(vn_TmpCurrCtr).thetype
            AND thecoat = 'B'
            AND numlength = oTheLengthDemandDates(vn_TmpCurrCtr).thelength;
          --exception
          --  when NO_DATA_FOUND -- Removed FEB2013
          --  then vn_TotNU := 0;
          --end;
          
          --begin
            SELECT quantity INTO vn_TotSM
            FROM reco_rstx_originvqty
            WHERE category_set_id = nCSetR
            AND thepunch = 'SM'
            AND thetype = oTheLengthDemandDates(vn_TmpCurrCtr).thetype
            AND thecoat = 'B'
            AND numlength = oTheLengthDemandDates(vn_TmpCurrCtr).thelength;
          --exception
          --  when NO_DATA_FOUND -- Removed FEB2013
          --  then vn_TotSM := 0;
          --end;
          
          vn_CurrQtyRawStl := vn_TotNU + vn_TotSM;
        END;
        
        --begin
          SELECT quantity INTO vn_CurrQtyNPBAvail
          FROM reco_rstx_originvqty
          WHERE category_set_id = nCSetN
          AND thepunch = 'N'
          AND thetype = oTheLengthDemandDates(vn_TmpCurrCtr).thetype
          AND thecoat = 'B'
          AND numlength = oTheLengthDemandDates(vn_TmpCurrCtr).thelength;
        --exception
        --  when NO_DATA_FOUND -- Removed FEB2013
        --  then vn_CurrQtyNPBAvail := 0;
        --end;
        
        --begin
        --  select quantity into vn_CurrQtyNPGAvail
        --  from reco_rstx_originvqty
        --  where category_set_id = nCSetN
        --  and thepunch = 'N'
        --  and thetype = oTheLengthDemandDates(vn_TmpCurrCtr).thetype
        --  and thecoat = 'G'
        --  and numlength = oTheLengthDemandDates(vn_TmpCurrCtr).thelength;
        --exception
        --  when NO_DATA_FOUND
        --  then vn_CurrQtyNPGAvail := 0;
        --end;
        
        --begin
          SELECT quantity INTO vn_CurrQtySPB
          FROM reco_rstx_originvqty
          WHERE category_set_id = nCSetB
          AND thepunch = 'S'
          AND thetype = oTheLengthDemandDates(vn_TmpCurrCtr).thetype
          AND thecoat = 'B'
          AND numlength = oTheLengthDemandDates(vn_TmpCurrCtr).thelength;
        --exception
        --  when NO_DATA_FOUND -- Removed FEB2013
        --  then vn_CurrQtySPB := 0;
        --end;
        
        --begin
          SELECT quantity INTO vn_CurrQtySPG
          FROM reco_rstx_originvqty
          WHERE category_set_id = nCSetG
          AND thepunch = 'S'
          AND thetype = oTheLengthDemandDates(vn_TmpCurrCtr).thetype
          AND thecoat = 'G'
          AND numlength = oTheLengthDemandDates(vn_TmpCurrCtr).thelength;
        --exception
        --  when NO_DATA_FOUND -- Removed FEB2013
        --  then vn_CurrQtySPG := 0;
        --end;
        
        --begin
          SELECT quantity INTO vn_CurrQtyDPB
          FROM reco_rstx_originvqty
          WHERE category_set_id = nCSetB
          AND thepunch = 'D'
          AND thetype = oTheLengthDemandDates(vn_TmpCurrCtr).thetype
          AND thecoat = 'B'
          AND numlength = oTheLengthDemandDates(vn_TmpCurrCtr).thelength;
        --exception
        --  when NO_DATA_FOUND -- Removed FEB2013
        --  then vn_CurrQtyDPB := 0;
        --end;
        
        --begin
          SELECT quantity INTO vn_CurrQtyDPG
          FROM reco_rstx_originvqty
          WHERE category_set_id = nCSetG
          AND thepunch = 'D'
          AND thetype = oTheLengthDemandDates(vn_TmpCurrCtr).thetype
          AND thecoat = 'G'
          AND numlength = oTheLengthDemandDates(vn_TmpCurrCtr).thelength;
        --exception
        --  when NO_DATA_FOUND -- Removed FEB2013
        --  then vn_CurrQtyDPG := 0;
        --end;
        
      END IF; -- Reset if we are looking at a new partlength / parttype
      
      ----------
      -- Set start of day inventory for this parttype/partlength
      ----------
      
      --rec_CurrCalc.rawsteel_start_inv :=
      --  vn_CurrQtyRawStl;
      
      --rec_CurrCalc.black_sp_daystrt_inv :=
      --  vn_CurrQtySPB;
      
      rec_CurrCalc.galv_sp_daystrt_inv :=
        vn_CurrQtySPG;
      
      --rec_CurrCalc.black_dp_daystrt_inv :=
      --  vn_CurrQtyDPB;
      
      rec_CurrCalc.galv_dp_daystrt_inv :=
        vn_CurrQtyDPG;
      
      ----------
      -- Set day demand for this date for this parttype/partlength
      ----------
      
      --select  sum(rsp.quantity)
      --into  rec_CurrCalc.black_sp_daydmnd
      --from  reco_shipment_parts rsp,
      --      reco_shipment rs,
      --      reco_rstx_originvqty roiq
      --where rs.shipment_id = rsp.shipment_id
      --and rsp.orig_subinventory_code in ('RSTX')
      --and rs.shipment_status in ('APPROVED','HOLD','BACKORDER')
      --and rs.shipment_date
      --        >= TRUNC(oTheLengthDemandDates(vn_TmpCurrCtr).thedate)
      --and rs.shipment_date
      --        < TRUNC(oTheLengthDemandDates(vn_TmpCurrCtr).thedate) + 1
      --and rsp.part_id = roiq.inventory_item_id
      --and roiq.thepunch = 'S'
      --and roiq.thetype = oTheLengthDemandDates(vn_TmpCurrCtr).thetype
      --and roiq.thecoat = 'B'
      --and roiq.numlength = oTheLengthDemandDates(vn_TmpCurrCtr).thelength;
      --
      --rec_CurrCalc.black_sp_daydmnd := nvl(rec_CurrCalc.black_sp_daydmnd,0);
      
      SELECT  SUM(rsp.quantity)
      INTO  rec_CurrCalc.galv_sp_daydmnd
      FROM  reco_truckstop_parts rsp,
            reco_truck rs,
            reco_rstx_originvqty roiq
      WHERE rs.truck_id = rsp.stop_truck_id
      AND rsp.orig_subinventory_code IN ('RSTX')
      AND rs.truck_status IN ('A','H','B')
      AND rs.truck_date
              >= TRUNC(oTheLengthDemandDates(vn_TmpCurrCtr).thedate)
      AND rs.truck_date
              < TRUNC(oTheLengthDemandDates(vn_TmpCurrCtr).thedate) + 1
      AND rsp.part_id = roiq.inventory_item_id
      AND roiq.thepunch = 'S'
      AND roiq.thetype = oTheLengthDemandDates(vn_TmpCurrCtr).thetype
      AND roiq.thecoat = 'G'
      AND roiq.numlength = oTheLengthDemandDates(vn_TmpCurrCtr).thelength;
      
      rec_CurrCalc.galv_sp_daydmnd := NVL(rec_CurrCalc.galv_sp_daydmnd,0);
      
      --select  sum(rsp.quantity)
      --into  rec_CurrCalc.black_dp_daydmnd
      --from  reco_shipment_parts rsp,
      --      reco_shipment rs,
      --      reco_rstx_originvqty roiq
      --where rs.shipment_id = rsp.shipment_id
      --and rsp.orig_subinventory_code in ('RSTX')
      --and rs.shipment_status in ('APPROVED','HOLD','BACKORDER')
      --and rs.shipment_date
      --        >= TRUNC(oTheLengthDemandDates(vn_TmpCurrCtr).thedate)
      --and rs.shipment_date
      --        < TRUNC(oTheLengthDemandDates(vn_TmpCurrCtr).thedate) + 1
      --and rsp.part_id = roiq.inventory_item_id
      --and roiq.thepunch = 'D'
      --and roiq.thetype = oTheLengthDemandDates(vn_TmpCurrCtr).thetype
      --and roiq.thecoat = 'B'
      --and roiq.numlength = oTheLengthDemandDates(vn_TmpCurrCtr).thelength;
      --
      --rec_CurrCalc.black_dp_daydmnd := nvl(rec_CurrCalc.black_dp_daydmnd,0);
      
      SELECT  SUM(rsp.quantity)
      INTO  rec_CurrCalc.galv_dp_daydmnd
      FROM  reco_truckstop_parts rsp,
            reco_truck rs,
            reco_rstx_originvqty roiq
      WHERE rs.truck_id = rsp.stop_truck_id
      AND rsp.orig_subinventory_code IN ('RSTX')
      AND rs.truck_status IN ('A','H','B')
      AND rs.truck_date
              >= TRUNC(oTheLengthDemandDates(vn_TmpCurrCtr).thedate)
      AND rs.truck_date
              < TRUNC(oTheLengthDemandDates(vn_TmpCurrCtr).thedate) + 1
      AND rsp.part_id = roiq.inventory_item_id
      AND roiq.thepunch = 'D'
      AND roiq.thetype = oTheLengthDemandDates(vn_TmpCurrCtr).thetype
      AND roiq.thecoat = 'G'
      AND roiq.numlength = oTheLengthDemandDates(vn_TmpCurrCtr).thelength;
      
      rec_CurrCalc.galv_dp_daydmnd := NVL(rec_CurrCalc.galv_dp_daydmnd,0);
      
      ----------
      -- Budget all new production.
      -- Ignore Black-to-Galvanizing conversion for now
      -- Ignore apply NoPunch-Black to All SP reqs and All DP reqs a needed
      -- Ignore raw-steel for now
      ----------
      
      IF vn_CurrQtyDPG >= rec_CurrCalc.galv_dp_daydmnd
      THEN
        rec_CurrCalc.galv_dp_use_newgalv := 0;
        vn_CurrQtyDPG := vn_CurrQtyDPG - rec_CurrCalc.galv_dp_daydmnd;
      ELSIF vn_CurrQtyDPG < rec_CurrCalc.galv_dp_daydmnd
      THEN
        rec_CurrCalc.galv_dp_use_newgalv :=
          rec_CurrCalc.galv_dp_daydmnd - vn_CurrQtyDPG;
        vn_CurrQtyDPG := 0;
      END IF;
      
      --if vn_CurrQtyDPB >= rec_CurrCalc.black_dp_daydmnd
      --then
      --  rec_CurrCalc.black_dp_use_newpun := 0;
      --  vn_CurrQtyDPB := vn_CurrQtyDPB - rec_CurrCalc.black_dp_daydmnd;
      --elsif vn_CurrQtyDPB < rec_CurrCalc.black_dp_daydmnd
      --then
      --  rec_CurrCalc.black_dp_use_newpun :=
      --    rec_CurrCalc.black_dp_daydmnd - vn_CurrQtyDPB;
      --  vn_CurrQtyDPB := 0;
      --end if;
      
      IF vn_CurrQtySPG >= rec_CurrCalc.galv_sp_daydmnd
      THEN
        rec_CurrCalc.galv_sp_use_newgalv := 0;
        vn_CurrQtySPG := vn_CurrQtySPG - rec_CurrCalc.galv_sp_daydmnd;
      ELSIF vn_CurrQtySPG < rec_CurrCalc.galv_sp_daydmnd
      THEN
        rec_CurrCalc.galv_sp_use_newgalv :=
          rec_CurrCalc.galv_sp_daydmnd - vn_CurrQtySPG;
        vn_CurrQtySPG := 0;
      END IF;
      
      --if vn_CurrQtySPB >= rec_CurrCalc.black_sp_daydmnd
      --then
      --  rec_CurrCalc.black_sp_use_newpun := 0;
      --  vn_CurrQtySPB := vn_CurrQtySPB - rec_CurrCalc.black_sp_daydmnd;
      --elsif vn_CurrQtySPB < rec_CurrCalc.black_sp_daydmnd
      --then
      --  rec_CurrCalc.black_sp_use_newpun :=
      --    rec_CurrCalc.black_sp_daydmnd - vn_CurrQtySPB;
      --  vn_CurrQtySPB := 0;
      --end if;
      
      ----------
      -- Apply Black-to-Galvanized conversion for galvanzied demand
      ----------
      --
      --rec_CurrCalc.galv_sp_convfromblk := 0;
      --rec_CurrCalc.galv_dp_convfromblk := 0;
      --
      --if rec_CurrCalc.galv_sp_use_newpun <= vn_CurrQtySPB
      --then
      --  rec_CurrCalc.galv_sp_convfromblk :=
      --    rec_CurrCalc.galv_sp_use_newpun;
      --  vn_CurrQtySPB :=
      --    vn_CurrQtySPB - rec_CurrCalc.galv_sp_use_newpun;
      --  rec_CurrCalc.galv_sp_use_newpun := 0;
      --elsif rec_CurrCalc.galv_sp_use_newpun > vn_CurrQtySPB
      --then
      --  rec_CurrCalc.galv_sp_convfromblk := vn_CurrQtySPB;
      --  rec_CurrCalc.galv_sp_use_newpun :=
      --    rec_CurrCalc.galv_sp_use_newpun - vn_CurrQtySPB;
      --  vn_CurrQtySPB := 0;
      --end if;
      --
      --if rec_CurrCalc.galv_dp_use_newpun <= vn_CurrQtyDPB
      --then
      --  rec_CurrCalc.galv_dp_convfromblk :=
      --    rec_CurrCalc.galv_dp_use_newpun;
      --  vn_CurrQtyDPB :=
      --    vn_CurrQtyDPB - rec_CurrCalc.galv_dp_use_newpun;
      --  rec_CurrCalc.galv_dp_use_newpun := 0;
      --elsif rec_CurrCalc.galv_dp_use_newpun > vn_CurrQtyDPB
      --then
      --  rec_CurrCalc.galv_dp_convfromblk := vn_CurrQtyDPB;
      --  rec_CurrCalc.galv_dp_use_newpun :=
      --    rec_CurrCalc.galv_dp_use_newpun - vn_CurrQtyDPB;
      --  vn_CurrQtyDPB := 0;
      --end if;
      
      ----------
      -- Apply any available raw steel to alleviate demand
      ----------
      
      --rec_CurrCalc.galv_sp_use_rawstl := 0;
      --rec_CurrCalc.black_sp_use_rawstl := 0;
      --rec_CurrCalc.galv_dp_use_rawstl := 0;
      --rec_CurrCalc.black_dp_use_rawstl := 0;
      --
      --if rec_CurrCalc.galv_dp_use_newpun <= vn_CurrQtyRawStl
      --then
      --  rec_CurrCalc.galv_dp_use_rawstl :=
      --    rec_CurrCalc.galv_dp_use_newpun;
      --  vn_CurrQtyRawStl :=
      --    vn_CurrQtyRawStl - rec_CurrCalc.galv_dp_use_newpun;
      --  rec_CurrCalc.galv_dp_use_newpun := 0;
      --elsif rec_CurrCalc.galv_dp_use_newpun > vn_CurrQtyRawStl
      --then
      --  rec_CurrCalc.galv_dp_use_rawstl :=
      --    vn_CurrQtyRawStl;
      --  rec_CurrCalc.galv_dp_use_newpun :=
      --    rec_CurrCalc.galv_dp_use_newpun - vn_CurrQtyRawStl;
      --  vn_CurrQtyRawStl := 0;
      --end if;
      --
      --if rec_CurrCalc.black_dp_use_newpun <= vn_CurrQtyRawStl
      --then
      --  rec_CurrCalc.black_dp_use_rawstl :=
      --    rec_CurrCalc.black_dp_use_newpun;
      --  vn_CurrQtyRawStl :=
      --    vn_CurrQtyRawStl - rec_CurrCalc.black_dp_use_newpun;
      --  rec_CurrCalc.black_dp_use_newpun := 0;
      --elsif rec_CurrCalc.black_dp_use_newpun > vn_CurrQtyRawStl
      --then
      --  rec_CurrCalc.black_dp_use_rawstl :=
      --    vn_CurrQtyRawStl;
      --  rec_CurrCalc.black_dp_use_newpun :=
      --    rec_CurrCalc.black_dp_use_newpun - vn_CurrQtyRawStl;
      --  vn_CurrQtyRawStl := 0;
      --end if;
      --
      --if rec_CurrCalc.galv_sp_use_newpun <= vn_CurrQtyRawStl
      --then
      --  rec_CurrCalc.galv_sp_use_rawstl :=
      --    rec_CurrCalc.galv_sp_use_newpun;
      --  vn_CurrQtyRawStl :=
      --    vn_CurrQtyRawStl - rec_CurrCalc.galv_sp_use_newpun;
      --  rec_CurrCalc.galv_sp_use_newpun := 0;
      --elsif rec_CurrCalc.galv_sp_use_newpun > vn_CurrQtyRawStl
      --then
      --  rec_CurrCalc.galv_sp_use_rawstl :=
      --    vn_CurrQtyRawStl;
      --  rec_CurrCalc.galv_sp_use_newpun :=
      --    rec_CurrCalc.galv_sp_use_newpun - vn_CurrQtyRawStl;
      --  vn_CurrQtyRawStl := 0;
      --end if;
      --
      --if rec_CurrCalc.black_sp_use_newpun <= vn_CurrQtyRawStl
      --then
      --  rec_CurrCalc.black_sp_use_rawstl :=
      --    rec_CurrCalc.black_sp_use_newpun;
      --  vn_CurrQtyRawStl :=
      --    vn_CurrQtyRawStl - rec_CurrCalc.black_sp_use_newpun;
      --  rec_CurrCalc.black_sp_use_newpun := 0;
      --elsif rec_CurrCalc.black_sp_use_newpun > vn_CurrQtyRawStl
      --then
      --  rec_CurrCalc.black_sp_use_rawstl :=
      --    vn_CurrQtyRawStl;
      --  rec_CurrCalc.black_sp_use_newpun :=
      --    rec_CurrCalc.black_sp_use_newpun - vn_CurrQtyRawStl;
      --  vn_CurrQtyRawStl := 0;
      --end if;
      ---- CONTINUE HERE RAWSTL REMOVED
      
      INSERT INTO reco_rstx_galvreqcalc
        (thedate,thelength,thetype,
          galv_dp_daystrt_inv,galv_dp_daydmnd,galv_dp_use_newgalv,
          galv_sp_daystrt_inv,galv_sp_daydmnd,galv_sp_use_newgalv)
      VALUES
        (rec_CurrCalc.thedate,
          rec_CurrCalc.thelength,
          rec_CurrCalc.thetype,
          rec_CurrCalc.galv_dp_daystrt_inv,
          rec_CurrCalc.galv_dp_daydmnd,
          rec_CurrCalc.galv_dp_use_newgalv,
          rec_CurrCalc.galv_sp_daystrt_inv,
          rec_CurrCalc.galv_sp_daydmnd,
          rec_CurrCalc.galv_sp_use_newgalv);
      
    END LOOP;
  END;
  
  INSERT INTO reco_rstx_galvreq
    (galvreq_id,reqdate,reqlength,reqtype,
      req_dp_g,req_sp_g,tot_qty_req,
      creation_date,created_by,last_update_date,last_updated_by,last_update_login)
  SELECT  reco_rstx_galvreq_seq.nextval,
          thedate,
          thelength,
          thetype,
          galv_dp_use_newgalv,
          galv_sp_use_newgalv,
          (
            galv_dp_use_newgalv +
            galv_sp_use_newgalv
          ),
          SYSDATE,-1,SYSDATE,-1,-1
  FROM
    (
      SELECT *
      FROM reco_rstx_galvreqcalc
      WHERE   galv_dp_use_newgalv > 0
      OR      galv_sp_use_newgalv > 0
      ORDER BY  TRUNC(thedate),
                thelength desc, -- Always analyze longer before shorter
                thetype
    );
  
END;  -- setup_galv_requirements

--------------------------------------------------------------------------------
-- get_firstdate_for_rpt
-- 
-- If the report shows shipments, then you should set the shipment
-- boolean to true. Otherwise, set it to false. (Logic Below)
-- 
-- To get the first date, pass DateNumber of 1...
-- To get the second date, pass DateNumber of 2...
-- 
-- The other two options are user parameters
-- 
-- If the report shows shipments, then there are times when the user
-- will leave APPROVED shipments open from a few days ago. So we would need
-- to get a date range that reaches back-in-time to get that open-shipment.
-- 
-- If the report does not show shipments, then we can go off the production
-- calendard (reco_rstx_calday) and check is_production_allowed too
-- 
-- Requirements:
-- You CANNOT run a report on HISTORY information if the report contains
-- shipment information (because we do not track shipment history information)
-- 
-- PRE-CONDITIONS
-- : In addition to the above,
--   when pi_TheReportShowsShipments is false then the caller must have
--   checked and passed the check_rpt_daterange_valid method
-- : APR2013 Decomissioned the pi_TheReportShowsShipments boolean
--   because shipment reports are very complex and specialized per-report basis
-- 
-- POST-CONDITIONS
-- : return 'DONE' if successful
-- : return an error message if failure
-- : If successful, then the output date is set to the desired date
--   indicated by parameters (see above text)
FUNCTION get_date_toshowin_rpt (pi_GivenHistId IN number,
                                pi_TheReportShowsShipments IN BOOLEAN,
                                pi_DateNumberToGet IN number,
                                pi_first_date_of_reqs IN date,
                                pi_first_date_of_cutting IN date,
                                po_OutDate OUT date)
RETURN varchar2
IS
  vd_Output date;
  
  vd_TmpFirst date;
BEGIN -- get_date_toshowin_rpt
  
  IF pi_TheReportShowsShipments IS NULL
  OR pi_GivenHistId IS NULL
  OR pi_DateNumberToGet IS NULL
  OR pi_DateNumberToGet <= 0
  OR pi_first_date_of_reqs IS NULL
  OR pi_first_date_of_cutting IS NULL
  OR pi_first_date_of_reqs > pi_first_date_of_cutting
  THEN
    po_OutDate := NULL;
    RETURN 'Internal Error 2054 - Invalid Params. Contact MIS';
  END IF;
  
  IF pi_TheReportShowsShipments = TRUE
  THEN
    po_OutDate := NULL;
    RETURN 'Internal Error 2055 - Shipment Rpt: Invalid Date Call. Contact MIS';
  END IF;
  
  SELECT thedate INTO vd_Output
  FROM
  (
    SELECT ROWNUM therownum, thedate
    FROM
    (
      SELECT thedate
      FROM reco_rstx_calday_hist
      WHERE cutsch_hist_id = pi_GivenHistId
      ORDER BY thedate
    )
  )
  WHERE therownum = pi_DateNumberToGet;
  
  po_OutDate := vd_Output;
  
  RETURN 'DONE';
END; -- get_date_toshowin_rpt

--------------------------------------------------------------------------------
PROCEDURE reset_debug_string
IS
BEGIN
  vc_DebugString := '';
END;

--------------------------------------------------------------------------------
FUNCTION get_debug_string RETURN varchar2
IS
BEGIN
  RETURN vc_DebugString;
END;

--------------------------------------------------------------------------------
-- check_rpt_daterange_valid
FUNCTION check_rpt_daterange_valid (pi_DesiredNumDays IN number)
RETURN VARCHAR2
IS
  vn_TmpHistId number;
  vc_OutMsg varchar2(1000);
BEGIN
  SELECT MAX(cutsch_hist_id) INTO vn_TmpHistId FROM reco_rstx_cutsch_hist;
  
  IF vn_TmpHistId IS NULL
  THEN
    RETURN 'Internal Error 2053 - Logging Dates are Corrupt. Contact MIS.';
  END IF;
  
  vc_OutMsg := check_rpt_daterange_valid(pi_DesiredNumDays,vn_TmpHistId);
  
  RETURN vc_OutMsg;
END;

--------------------------------------------------------------------------------
-- check_rpt_daterange_valid
-- 
-- We Log History information for the cut schedule.
-- This includes logging day-by-day information for each schedule.
-- 
-- : If somebody wants to
--   1) print a report based on CutSch from last year
--   -AND-
--   2) they want that report to show 3-weeks of data
--   -THEN-
--   The history information for that cutsch needs to hold 3-weeks worth of days
-- 
-- This method checks that the desired Log History has enough dates
-- for the desired reporting range
-- 
-- Requirements:
-- You CANNOT run a report on HISTORY information if the report contains
-- shipment information (because we do not track shipment history information)
-- (This is required by method get_date_toshowin_rpt)
-- 
-- So you CANNOT call this method on a report that shows shipment data
-- (and you can't call get_date_toshowin_rpt for that report either)
-- 
-- PRE-CONDITION
-- This assumes the report will NOT show shipment data
-- So we only handle the date range as if it does not depend on shipments
FUNCTION check_rpt_daterange_valid (pi_DesiredNumDays IN number,
                                    pi_GivenHistId IN number)
RETURN VARCHAR2
IS
BEGIN -- check_rpt_daterange_valid
  
  IF pi_DesiredNumDays > vn_MaxDaysToLogPerSch
  THEN
    RETURN
      'RECo Error: You cannot show '||TO_CHAR(pi_DesiredNumDays)||
      ' days for this report. Too many days';
  END IF;
  
  -- This query should be a copy from the get_date_toshowin_rpt method
  DECLARE
    vd_TmpDate date;
  BEGIN
    SELECT thedate INTO vd_TmpDate
    FROM
    (
      SELECT ROWNUM therownum, thedate
      FROM
      (
        SELECT thedate
        FROM reco_rstx_calday_hist
        WHERE cutsch_hist_id = pi_GivenHistId
        ORDER BY thedate
      )
    )
    WHERE therownum = pi_DesiredNumDays;
  EXCEPTION
    WHEN NO_DATA_FOUND
    THEN
      RETURN
        'RECo Error: You cannot show '||TO_CHAR(pi_DesiredNumDays)||
        ' days for this report. Too many days';
  END;
  
  RETURN 'DONE';
  
END; -- check_rpt_daterange_valid

--------------------------------------------------------------------------------
-- add_year_to_calen_auto
PROCEDURE add_year_to_calen_auto
IS
  PRAGMA AUTONOMOUS_TRANSACTION;
  
  vr_LastActualDate reco_rstx_calday%ROWTYPE;
  
  vn_NewYear number;
  
BEGIN -- add_year_to_calen_auto
  
  SELECT * INTO vr_LastActualDate FROM reco_rstx_calday
  WHERE thedate IN (SELECT MAX(thedate) FROM reco_rstx_calday);
  
  DECLARE
    vr_LastWorkingDate reco_rstx_calday%ROWTYPE;
  BEGIN
    SELECT * INTO vr_LastWorkingDate FROM reco_rstx_calday
    WHERE thedate IN (SELECT MAX(thedate)
                      FROM reco_rstx_calday
                      WHERE is_production_allowed = 'Y');
    
    vr_LastActualDate.qty_bars_max :=
      vr_LastWorkingDate.qty_bars_max;
    vr_LastActualDate.qty_bars_per_run := 
      vr_LastWorkingDate.qty_bars_per_run;
  END;
  
  LOOP
    IF TO_CHAR(vr_LastActualDate.theDate,'DD-MON') = '31-DEC'
    THEN exit;
    END IF;
    
    vr_LastActualDate.theDate := vr_LastActualDate.theDate + 1;
    
    vr_LastActualDate.is_production_allowed := 'Y';
    IF TO_CHAR(vr_LastActualDate.theDate,'DY') IN ('SAT','SUN')
    THEN vr_LastActualDate.is_production_allowed := 'N';
    END IF;
    
    SELECT reco_rstx_calday_seq.nextval INTO vr_LastActualDate.calday_id FROM dual;
    
    INSERT INTO reco_rstx_calday (calday_id,thedate,qty_bars_max,
      qty_bars_per_run,is_production_allowed,last_update_date,
      last_updated_by,creation_date,created_by,last_update_login)
    VALUES (vr_LastActualDate.calday_id,vr_LastActualDate.thedate,
            vr_LastActualDate.qty_bars_max,vr_LastActualDate.qty_bars_per_run,
            vr_LastActualDate.is_production_allowed,
            SYSDATE,-1,SYSDATE,-1,-1);
    
    add_pockets_for_day(vr_LastActualDate.calday_id);
    
  END LOOP;
  
  vn_NewYear := TO_NUMBER(TO_CHAR(vr_LastActualDate.theDate,'YYYY')) + 1;
  
  LOOP
    IF '01-JAN-'||TO_CHAR(vn_NewYear+1)
          = TO_CHAR(vr_LastActualDate.theDate,'DD-MON-YYYY')
    THEN exit;
    END IF;
    
    vr_LastActualDate.theDate := vr_LastActualDate.theDate + 1;
    
    vr_LastActualDate.is_production_allowed := 'Y';
    IF TO_CHAR(vr_LastActualDate.theDate,'DY') IN ('SAT','SUN')
    THEN vr_LastActualDate.is_production_allowed := 'N';
    END IF;
    
    SELECT reco_rstx_calday_seq.nextval INTO vr_LastActualDate.calday_id FROM dual;
    
    INSERT INTO reco_rstx_calday (calday_id,thedate,qty_bars_max,
      qty_bars_per_run,is_production_allowed,last_update_date,
      last_updated_by,creation_date,created_by,last_update_login)
    VALUES (vr_LastActualDate.calday_id,vr_LastActualDate.thedate,
            vr_LastActualDate.qty_bars_max,vr_LastActualDate.qty_bars_per_run,
            vr_LastActualDate.is_production_allowed,
            SYSDATE,-1,SYSDATE,-1,-1);
    
    add_pockets_for_day(vr_LastActualDate.calday_id);
    
  END LOOP;
  
  COMMIT; -- Required for autonomous transaction
  RETURN;
END; -- add_year_to_calen_auto

--------------------------------------------------------------------------------
PROCEDURE log_reporting_history(pi_UserName IN varchar2,
                                pi_DescriptionToLog IN varchar2)
IS
  PRAGMA AUTONOMOUS_TRANSACTION;
  
  vn_MaxQtyRptHistItems number;
  vn_CurrQtyRptHistItems number;
BEGIN -- log_reporting_history
  
  vn_MaxQtyRptHistItems := 75;
  
  SELECT COUNT(*) INTO vn_CurrQtyRptHistItems FROM reco_rstx_reporting_hist;
  
  INSERT INTO reco_rstx_reporting_hist
    (reporting_hist_id,thetime,theusername,description)
  SELECT reco_rstx_reporting_hist_seq.nextval, SYSDATE,
          pi_UserName, pi_DescriptionToLog FROM dual;
  
  vn_CurrQtyRptHistItems := vn_CurrQtyRptHistItems + 1;
  
  IF vn_CurrQtyRptHistItems > vn_MaxQtyRptHistItems
  THEN
    DELETE FROM reco_rstx_reporting_hist
    WHERE reporting_hist_id IN (SELECT MIN(subTbl.reporting_hist_id)
                                FROM reco_rstx_reporting_hist subTbl);
    
    vn_CurrQtyRptHistItems := vn_CurrQtyRptHistItems - 1;
  END IF;
  
  COMMIT;
END; -- log_reporting_history

--------------------------------------------------------------------------------
-- set_user_parameters
-- 
-- pi_MinimumCutToAnalyze : Best leave at 8 / 6, be sure to check rare lengths
-- pi_MaximumCutToAnalyze : Best leave at 32 / 38, be sure to check rare lengths
-- pi_NumCreatedPerRun in number,
-- pi_LastPriorityDate : Should at least by SYSDATE + 1, because we require stuff to be done
--                       at least one day ahead of schedule
-- pi_FirstDateOfReqs IN date,
-- pi_FirstDayToSchedCuts in date,
-- pi_LastDayToShowInRpts in date,
FUNCTION set_user_parameters( pi_raw_bar_size IN number,
                              pi_min_cut_allowed IN number,
                              pi_max_cut_allowed IN number,
                              pi_safety_days_out IN number,
                              pi_rare_length_days_out IN number,
                              pi_largerbars_near_machine IN varchar2,
                              pi_show_cutrpt_100incrs IN varchar2,
                              pi_ignore_curr_np_inv IN varchar2,
                              pi_first_date_of_reqs IN date,
                              pi_first_date_of_cutting IN date)
RETURN varchar2
IS
BEGIN -- set_user_parameters
  IF pi_raw_bar_size IS NULL
  OR pi_min_cut_allowed IS NULL
  OR pi_max_cut_allowed IS NULL
  OR pi_safety_days_out IS NULL
  OR pi_rare_length_days_out IS NULL
  OR pi_largerbars_near_machine IS NULL
  OR pi_show_cutrpt_100incrs IS NULL
  OR pi_ignore_curr_np_inv IS NULL
  OR pi_first_date_of_reqs IS NULL
  OR pi_first_date_of_cutting IS NULL
  THEN
    RETURN 'Internal Error 2013 - Invalid parameters';
  END IF;
  
  DELETE FROM reco_rstx_userparam;
  
  INSERT INTO reco_rstx_userparam
    (USERPARAM_ID,RAW_BAR_SIZE,MIN_CUT_ALLOWED,MAX_CUT_ALLOWED,
      SAFETY_DAYS_OUT,RARE_LENGTH_DAYS_OUT,
      LARGERBARS_NEAR_MACHINE,SHOW_CUTRPT_100INCRS,IGNORE_CURR_NP_INV,
      FIRST_DATE_OF_REQS,FIRST_DATE_OF_CUTTING,
      LAST_UPDATE_DATE,LAST_UPDATED_BY,CREATION_DATE,
      CREATED_BY,LAST_UPDATE_LOGIN)
  SELECT  reco_rstx_userparam_seq.nextval,
          pi_raw_bar_size,pi_min_cut_allowed,pi_max_cut_allowed,
          pi_safety_days_out,pi_rare_length_days_out,
          pi_largerbars_near_machine,pi_show_cutrpt_100incrs,
          pi_ignore_curr_np_inv,
          pi_first_date_of_reqs,pi_first_date_of_cutting,
          SYSDATE,-1,SYSDATE,-1,-1
  FROM dual;
  
  RETURN 'DONE';
END; -- set_user_parameters

--------------------------------------------------------------------------------
-- scroll_parameter_dates
PROCEDURE scroll_parameter_dates (errbuf OUT varchar2, retcode OUT number)
IS
  vr_Params reco_rstx_userparam%ROWTYPE;
  vc_TmpOutput varchar2(1000);
BEGIN -- scroll_parameter_dates
  
  BEGIN
    SELECT * INTO vr_Params FROM reco_rstx_userparam;
  EXCEPTION
    WHEN others
    THEN
      errbuf := 'Completed Normal';
      retcode := 0;
      RETURN;
  END;
  
  DECLARE
    vn_QtyDaysFCToFR number; -- Qty Days first-cut-date to first-report-date
  BEGIN
    vn_QtyDaysFCToFR :=
      ABS(vr_Params.first_date_of_cutting - vr_Params.first_date_of_reqs);
    
    vr_Params.first_date_of_cutting := TRUNC(SYSDATE);
    vr_Params.first_date_of_reqs :=
      vr_Params.first_date_of_cutting - vn_QtyDaysFCToFR;
  END;
  
  UPDATE reco_rstx_userparam
  set last_update_date = SYSDATE,
      last_updated_by = -1,
      last_update_login = -1,
      first_date_of_reqs = vr_Params.first_date_of_reqs,
      first_date_of_cutting = vr_Params.first_date_of_cutting;
  
  COMMIT;
  
  vc_TmpOutput := run_cut_optimize('NIGHTLY AUTO REFRESH');
  
  log_reporting_history('NIGHTLY AUTO REFRESH','Schedule is Refreshed');
  
  errbuf := 'Completed Normal';
  retcode := 0;
  
EXCEPTION
  WHEN others
  THEN
    FND_FILE.put_line(fnd_file.Log, 'Error scroll_parameter_dates');
    errbuf := SQLERRM;
    retcode := 1;
END; -- scroll_parameter_dates

--------------------------------------------------------------------------------
-- run_cut_optimize
-- 
-- Clears all cutting information / schedule information and regenerates
-- the cutting plan
FUNCTION run_cut_optimize (pi_UserName IN varchar2)
RETURN varchar2
IS
  vc_ReturnStatus varchar2(1000);
  
  vr_Params reco_rstx_userparam%ROWTYPE;
BEGIN -- run_cut_optimize
  
  BEGIN
    SELECT * INTO vr_Params FROM reco_rstx_userparam;
  EXCEPTION
    WHEN NO_DATA_FOUND
    THEN RETURN 'Internal Error 2014 - No parameters detected. Contact MIS.';
    WHEN TOO_MANY_ROWS
    THEN RETURN 'Internal Error 2015 - Parameters are corrupted. Contact MIS.';
  END;
  
  clear_existing_reqsandplans;
  
  vc_ReturnStatus := validate_and_count_inv(vr_Params.first_date_of_reqs,
                        vr_Params.min_cut_allowed,vr_Params.max_cut_allowed);
  
  IF vc_ReturnStatus != 'DONE'
  THEN RETURN vc_ReturnStatus;
  END IF;
  
  ----------------------------------------------------------
  -- Fill the table: reco_rstx_cutreq
  ----------------------------------------------------------
  
  setup_cut_requirements(
    vr_Params.first_date_of_reqs,
    vr_Params.min_cut_allowed,
    vr_Params.max_cut_allowed,
    vr_Params.ignore_curr_np_inv);
  
  ----------------------------------------------------------
  -- Fill the temporary table: reco_rstx_cutmtx_lenpunmap
  -- in preparation to allow special punches
  ----------------------------------------------------------
  
  setup_cutmtx_allowed_lenpuns;
  
  ----------------------------------------------------------
  -- Make sure enough calendar days exist
  ----------------------------------------------------------
  
  DECLARE
    vd_LastCalDate date;
    vd_LastReqDate date;
  BEGIN
    SELECT MAX(thedate) INTO vd_LastCalDate FROM reco_rstx_calday;
    
    SELECT MAX(reqdate) INTO vd_LastReqDate FROM reco_rstx_cutreqv2;
    
    IF vd_LastCalDate < vd_LastReqDate + 149
    THEN add_year_to_calen_auto;
     -- CONTINUE HERE THIS SHOULD USE A LOOP TO ADD MULTIPLE YEARS
     -- (e.g. when the shedule hasn't been run for a long time...)
    END IF;
  END;
  
  ----------------------------------------------------------
  -- Fill the tables:
  -- : reco_rstx_cutrun
  -- : reco_rstx_cutasg
  -- : reco_rstx_day_pkt_bin
  -- : reco_rstx_run_placement
  ----------------------------------------------------------
  
  ----------------------------------------------------------
  -- Loop for each date that the user wants to see,
  -- and fill cuts / pockets on those dates
  -- (e.g. regen all values in:
  --       : reco_rstx_cutrunv2
  --       : reco_rstx_cutasgv2
  --       : reco_rstx_cutovg
  --       : reco_rstx_day_pkt_bin
  --       : reco_rstx_run_placement
  -- )
  ----------------------------------------------------------
  DECLARE
    vd_LastSafetyDate date;
    
    vc_OutputFromAssignFn varchar2(1000);
  BEGIN
    
    SELECT thedate INTO vd_LastSafetyDate
    FROM
    (
      SELECT ROWNUM therownum, thedate
      FROM
      (
        SELECT thedate
        FROM reco_rstx_calday calday
        WHERE is_production_allowed = 'Y'
        AND thedate >= vr_Params.first_date_of_cutting
        ORDER BY thedate
      )
    )
    WHERE therownum = vr_Params.safety_days_out + 1; -- CONTINUE HERE CORRECT DAY?
    
    FOR rec_ThisCutDate IN
      (
        SELECT calday.thedate
        FROM reco_rstx_calday calday
        WHERE calday.thedate >= vr_Params.first_date_of_cutting
        AND calday.thedate <= vd_LastSafetyDate -- CONTINUE HERE CORRECT DAY?
        AND calday.is_production_allowed = 'Y'
        ORDER BY calday.thedate
      )
    LOOP  -- Loop for each day we care about
      
      --if cur_cutdates%NOTFOUND
      --or rec_ThisCutDate.thedate > vr_Params.last_date_to_view
      --then exit;
      --end if;
      
      FOR rec_ptype IN
        (
          SELECT DISTINCT daypocket.parttype thetype
          FROM reco_rstx_calday calday, reco_rstx_day_pocket daypocket
          WHERE calday.calday_id = daypocket.calday_id
          AND calday.thedate = rec_ThisCutDate.thedate
          AND daypocket.parttype != '504'
        )
      LOOP
        vc_OutputFromAssignFn := fill_rarelen_reqs(
          vr_Params.raw_bar_size,rec_ptype.thetype,
          rec_ThisCutDate.thedate,
          vr_Params.min_cut_allowed,vr_Params.max_cut_allowed,
          vr_Params.rare_length_days_out);
        
        IF vc_OutputFromAssignFn != 'DONE'
        THEN ROLLBACK; RETURN vc_OutputFromAssignFn;
        END IF;
        
        vc_OutputFromAssignFn := assign_runs_for_daypart(
            vr_Params.raw_bar_size,rec_ptype.thetype,rec_ThisCutDate.thedate,
            vr_Params.min_cut_allowed,vr_Params.max_cut_allowed,
            vr_Params.safety_days_out);
        
        IF vc_OutputFromAssignFn != 'DONE'
        THEN ROLLBACK; RETURN vc_OutputFromAssignFn;
        END IF;
      END LOOP;
      
      vc_OutputFromAssignFn := fill_rarelen_reqs(
        vr_Params.raw_bar_size,'504',
        rec_ThisCutDate.thedate,
        vr_Params.min_cut_allowed,vr_Params.max_cut_allowed,
        vr_Params.rare_length_days_out);
      
      IF vc_OutputFromAssignFn != 'DONE'
      THEN ROLLBACK; RETURN vc_OutputFromAssignFn;
      END IF;
      
      vc_OutputFromAssignFn := assign_runs_for_daypart(
          vr_Params.raw_bar_size,'504',rec_ThisCutDate.thedate,
          vr_Params.min_cut_allowed,vr_Params.max_cut_allowed,
          vr_Params.safety_days_out);
      
      IF vc_OutputFromAssignFn != 'DONE'
      THEN ROLLBACK; RETURN vc_OutputFromAssignFn;
      END IF;
      
      -- CONTINUE HERE
      --try_to_fill_rest_of_day_when_all_pkts_have
      -- _matrices_but_you_are_still_short_of_total_day_qty()
      --Which can happen if you have rare-lengths clogging pockets
      --or you just don't need a lot of one-specific matrix
      
      set_bin_labels(rec_ThisCutDate.thedate,
            vr_Params.largerbars_near_machine);
    END LOOP;
    
  END;
  
  ----------------------------------------------------------
  -- Fill the table: reco_rstx_punreq
  ----------------------------------------------------------
  
  setup_punch_requirements(
    vr_Params.first_date_of_reqs,
    vr_Params.min_cut_allowed,
    vr_Params.max_cut_allowed);
  
  ----------------------------------------------------------
  -- Fill the table: reco_rstx_punasg
  ----------------------------------------------------------
  
  -- We have generated the cut schedule
  -- Now figure out how to punch existing inventory
  
  -- This PUNCH schedule is MUCH EASIER than the CUT schedule
  -- : We don't have to worry about selecting a cut matrix
  -- : We don't have to worry about one run producing different lengths
  -- : We don't need to assign bins or pockets
  -- : Lots of other reasons
  
  DECLARE
    vc_Temp number;
    vc_OutputFromAssignFn varchar2(1000);
  BEGIN
    FOR rec_ThisPunchDate IN
      (
        SELECT calday.thedate
        FROM reco_rstx_calday calday
        WHERE calday.thedate >= vr_Params.first_date_of_cutting
        AND calday.thedate <= vr_Params.first_date_of_cutting + 20-- CONTINUE HERE
        AND calday.is_production_allowed = 'Y'
        ORDER BY calday.thedate
      )
    LOOP
      BEGIN
        SELECT 1 INTO vc_Temp
        FROM
              (
                SELECT  SUM(punreq.tot_qty_req) totQty
                FROM  reco_rstx_punreq punreq
              ) subQReq,
              (
                SELECT  SUM(punasg.qty_asg_black + punasg.qty_asg_galv) totQty
                FROM  reco_rstx_punasg punasg
              ) subQAsg
        WHERE subQReq.totQty > NVL(subQAsg.totQty,0);
      EXCEPTION
        WHEN NO_DATA_FOUND
        THEN
          exit;
        WHEN TOO_MANY_ROWS
        THEN
          NULL;
        WHEN others
        THEN
          vc_OutputFromAssignFn := 'Intenal Error at Punch-Date handling';
          ROLLBACK; RETURN vc_OutputFromAssignFn;
      END;
      
      vc_OutputFromAssignFn := assign_punch_runs(rec_ThisPunchDate.thedate);
      
      IF vc_OutputFromAssignFn != 'DONE'
      THEN ROLLBACK; RETURN vc_OutputFromAssignFn;
      END IF;
    END LOOP;
  END;
  
  ----------------------------------------------------------
  -- Fill the table: reco_rstx_galvreq
  ----------------------------------------------------------
  
  -- We have generated the cut schedule
  -- We have generated the punch schedule
  -- Now figure out how to galvanize existing inventory
  -- : This does NOT consider CutSch NP results for inventory/processing
  -- : This does NOT consider PunSch SP/DP results for inventory/processing
  -- : This does NOT consider rawsteel available for galvanizing
  --   (because when would we ever galvanize raw steel?)
  
  setup_galv_requirements(
    vr_Params.first_date_of_reqs,
    vr_Params.min_cut_allowed,
    vr_Params.max_cut_allowed);
  
  -- Now we need to log cutschedule data for future reference
  -- (like in the manufacturing form)
  
  DECLARE
    vn_MaxQtyHistItems number;
    
    vn_NewHistId number;
    
    vn_CurrQtyHistItems number;
    vn_OldestHistId number;
    
    vd_FirstProdDateToRecord date;
    vd_LastProdDateToRecord date;
  BEGIN
    
    vn_MaxQtyHistItems := 15;
    
    SELECT reco_rstx_cutsch_hist_seq.nextval INTO vn_NewHistId FROM dual;
    
    SELECT COUNT(cutsch_hist_id), MIN(cutsch_hist_id)
    INTO vn_CurrQtyHistItems, vn_OldestHistId
    FROM reco_rstx_cutsch_hist;
    
    SELECT MIN(thedate) INTO vd_FirstProdDateToRecord
    FROM reco_rstx_calday calday
    WHERE is_production_allowed = 'Y'
    AND thedate >= vr_Params.first_date_of_cutting
    ORDER BY thedate;
    
    SELECT thedate INTO vd_LastProdDateToRecord
    FROM
    (
      SELECT ROWNUM therownum, thedate
      FROM
      (
        SELECT thedate
        FROM reco_rstx_calday calday
        WHERE is_production_allowed = 'Y'
        AND thedate >= vr_Params.first_date_of_cutting
        ORDER BY thedate
      )
    )
    WHERE therownum = vn_MaxDaysToLogPerSch;
    
    INSERT INTO reco_rstx_cutsch_hist
    (cutsch_hist_id,thetime,theusername,runname)
    VALUES
    (vn_NewHistId,SYSDATE,pi_UserName,
      TO_CHAR(SYSDATE,'DD-MON HH:MIAM')||'-'||pi_UserName);
    
    INSERT INTO reco_rstx_originvqty_hist
    (cutsch_hist_id,originvqty_id,inventory_item_id,quantity,
      actual_attribute4,segment1,category_set_id,
      thepunch,thetype,thecoat,numlength,charlength,
      min_minmax_quantity,max_minmax_quantity)
    (
      SELECT  vn_NewHistId,
              originvqty_id,
              inventory_item_id,
              quantity,
              actual_attribute4,
              segment1,
              category_set_id,
              thepunch,
              thetype,
              thecoat,
              numlength,
              charlength,
              min_minmax_quantity,
              max_minmax_quantity
      FROM  reco_rstx_originvqty
    );
    
    INSERT INTO reco_rstx_userparam_hist
    ( CUTSCH_HIST_ID,USERPARAM_ID,RAW_BAR_SIZE,
      MIN_CUT_ALLOWED,MAX_CUT_ALLOWED,SAFETY_DAYS_OUT,
      RARE_LENGTH_DAYS_OUT,LARGERBARS_NEAR_MACHINE,
      SHOW_CUTRPT_100INCRS,IGNORE_CURR_NP_INV,
      FIRST_DATE_OF_REQS,FIRST_DATE_OF_CUTTING)
    (
      SELECT  vn_NewHistId,
              userparam_id,
              raw_bar_size,
              min_cut_allowed,
              max_cut_allowed,
              safety_days_out,
              rare_length_days_out,
              largerbars_near_machine,
              show_cutrpt_100incrs,
              ignore_curr_np_inv,
              first_date_of_reqs,
              first_date_of_cutting
      FROM reco_rstx_userparam
    );
    
    INSERT INTO reco_rstx_calday_hist
    ( CUTSCH_HIST_ID,CALDAY_ID,THEDATE,
      QTY_BARS_MAX,QTY_BARS_PER_RUN,IS_PRODUCTION_ALLOWED)
    (
      SELECT  vn_NewHistId,
              calday.calday_id,
              calday.thedate,
              calday.qty_bars_max,
              calday.qty_bars_per_run,
              calday.is_production_allowed
      FROM reco_rstx_calday calday
      --where calday.calday_id in -- DSM REMOVED APRIL 24TH TO ALLOW MORE HISTORY
      --              ( select daypkt.calday_id
      --                from reco_rstx_day_pocket daypkt
      --                where daypkt.day_pocket_id in
      --                              ( select daypktbin.day_pocket_id
      --                                from reco_rstx_day_pkt_bin daypktbin ) )
      WHERE calday.thedate >= vd_FirstProdDateToRecord
      AND calday.thedate <= vd_LastProdDateToRecord
    );
    
    INSERT INTO reco_rstx_daypkt_hist
    (CUTSCH_HIST_ID,DAY_POCKET_ID,CALDAY_ID,STORAGE_CAPACITY,
      POCKET_NUMBER,PARTTYPE,MAX_LENGTH)
    (
      SELECT  vn_NewHistId,
              daypocket.day_pocket_id,
              daypocket.calday_id,
              daypocket.storage_capacity,
              daypocket.pocket_number,
              daypocket.parttype,
              daypocket.max_length
      FROM  reco_rstx_day_pocket daypocket,
            reco_rstx_calday calday
      WHERE   daypocket.calday_id = calday.calday_id
      AND     calday.thedate >= vd_FirstProdDateToRecord
      AND     calday.thedate <= vd_LastProdDateToRecord
    );
    
    INSERT INTO reco_rstx_daypktbin_hist
    (CUTSCH_HIST_ID,DAY_PKT_BIN_ID,DAY_POCKET_ID,LENGTH_OF_PART,
      LENGTH_USED,FIRST_MACHINE_LABEL,LAST_MACHINE_LABEL)
    (
      SELECT  vn_NewHistId,
              daypktbin.day_pkt_bin_id,
              daypktbin.day_pocket_id,
              daypktbin.length_of_part,
              daypktbin.length_used,
              daypktbin.first_machine_label,
              daypktbin.last_machine_label
      FROM  reco_rstx_day_pkt_bin daypktbin,
            reco_rstx_day_pocket daypocket,
            reco_rstx_calday calday
      WHERE   daypktbin.day_pocket_id = daypocket.day_pocket_id
      AND     daypocket.calday_id = calday.calday_id
      AND     calday.thedate >= vd_FirstProdDateToRecord
      AND     calday.thedate <= vd_LastProdDateToRecord
    );
    
    INSERT INTO reco_rstx_runplac_hist
    (CUTSCH_HIST_ID,PLACEMENT_ID,CUTRUN_ID,DAY_PKT_BIN_ID,QTY_PLACED)
    (
      SELECT  vn_NewHistId,
              placement.placement_id,
              placement.cutrun_id,
              placement.day_pkt_bin_id,
              placement.qty_placed
      FROM  reco_rstx_run_placement placement,
            reco_rstx_day_pkt_bin daypktbin,
            reco_rstx_day_pocket daypocket,
            reco_rstx_calday calday
      WHERE   placement.day_pkt_bin_id = daypktbin.day_pkt_bin_id
      AND     daypktbin.day_pocket_id = daypocket.day_pocket_id
      AND     daypocket.calday_id = calday.calday_id
      AND     calday.thedate >= vd_FirstProdDateToRecord
      AND     calday.thedate <= vd_LastProdDateToRecord
    );
    
    INSERT INTO reco_rstx_cutrun_hist
    (CUTSCH_HIST_ID,CUTRUN_ID,RUN_NUMBER,CUTPCE_ID,QTY_BARS_PROCESSED)
    (
      SELECT  vn_NewHistId,
              cutrun.cutrun_id,
              cutrun.run_number,
              cutrun.cutpce_id,
              cutrun.qty_bars_processed
      FROM  reco_rstx_cutrun cutrun
    ); 
    
    INSERT INTO reco_rstx_cutovg_hist
    (CUTSCH_HIST_ID,CUTOVG_ID,CUTRUN_ID,OVERAGE_QTY)
    (
      SELECT  vn_NewHistId,
              cutovg.cutovg_id,
              cutovg.cutrun_id,
              cutovg.overage_qty
      FROM  reco_rstx_cutovg cutovg
    );
    
    INSERT INTO reco_rstx_cutreqv2_hist
    (CUTSCH_HIST_ID,CUTREQ_ID,
      REQDATE,REQLENGTH,REQTYPE,REQPUNCH,
      QTY_REQ_BLACK,QTY_REQ_GALV,
      QTY_DONE_CONVBTOG,
      QTY_DONE_BLACK_FROMRAWSTL,
      QTY_DONE_GALV_FROMRAWSTL,
      TOT_QTY_REQ)
    (
      SELECT  vn_NewHistId,
              cutreq.cutreq_id,
              cutreq.reqdate,
              cutreq.reqlength,
              cutreq.reqtype,
              cutreq.reqpunch,
              cutreq.qty_req_black,
              cutreq.qty_req_galv,
              cutreq.qty_done_convbtog,
              cutreq.qty_done_black_fromrawstl,
              cutreq.qty_done_galv_fromrawstl,
              cutreq.tot_qty_req
      FROM  reco_rstx_cutreqv2 cutreq
    );
    
    INSERT INTO reco_rstx_cutasgv2_hist
    (CUTSCH_HIST_ID,CUTASG_ID,CUTRUN_ID,CUTREQ_ID,
      QTY_ASG_BLACK,QTY_ASG_GALV)
    (
      SELECT  vn_NewHistId,
              cutasg.cutasg_id,
              cutasg.cutrun_id,
              cutasg.cutreq_id,
              cutasg.qty_asg_black,
              cutasg.qty_asg_galv
      FROM  reco_rstx_cutasgv2 cutasg
    );
    
    INSERT INTO reco_rstx_punrun_hist
    (CUTSCH_HIST_ID,PUNRUN_ID,CALDAY_ID,RUN_NUMBER,QTY_BARS_PROCESSED)
    (
      SELECT  vn_NewHistId,
              punrun.punrun_id,
              punrun.calday_id,
              punrun.run_number,
              punrun.qty_bars_processed
      FROM  reco_rstx_punrun punrun
    ); 
    
    INSERT INTO reco_rstx_punovg_hist
    (CUTSCH_HIST_ID,PUNOVG_ID,PUNRUN_ID,OVERAGE_QTY)
    (
      SELECT  vn_NewHistId,
              punovg.punovg_id,
              punovg.punrun_id,
              punovg.overage_qty
      FROM  reco_rstx_punovg punovg
    );
    
    INSERT INTO reco_rstx_punreq_hist
    (CUTSCH_HIST_ID,PUNREQ_ID,
      REQDATE,REQLENGTH,REQTYPE,REQPUNCH,
      QTY_REQ_BLACK,QTY_REQ_GALV,
      QTY_DONE_CONVBTOG,TOT_QTY_REQ)
    (
      SELECT  vn_NewHistId,
              punreq.punreq_id,
              punreq.reqdate,
              punreq.reqlength,
              punreq.reqtype,
              punreq.reqpunch,
              punreq.qty_req_black,
              punreq.qty_req_galv,
              punreq.qty_done_convbtog,
              punreq.tot_qty_req
      FROM  reco_rstx_punreq punreq
    );
    
    INSERT INTO reco_rstx_punasg_hist
    (CUTSCH_HIST_ID,PUNASG_ID,
      PUNRUN_ID,PUNREQ_ID,
      QTY_ASG_BLACK,QTY_ASG_GALV)
    (
      SELECT  vn_NewHistId,
              punasg.punasg_id,
              punasg.punrun_id,
              punasg.punreq_id,
              punasg.qty_asg_black,
              punasg.qty_asg_galv
      FROM  reco_rstx_punasg punasg
    );
    
    INSERT INTO reco_rstx_galvreq_hist
    (CUTSCH_HIST_ID,GALVREQ_ID,REQDATE,REQLENGTH,
      REQTYPE,REQ_DP_G,REQ_SP_G,TOT_QTY_REQ)
    (
      SELECT  vn_NewHistId,
              galvreq.galvreq_id,
              galvreq.reqdate,
              galvreq.reqlength,
              galvreq.reqtype,
              galvreq.req_dp_g,
              galvreq.req_sp_g,
              galvreq.tot_qty_req
      FROM  reco_rstx_galvreq galvreq
    );
    
    vn_CurrQtyHistItems := vn_CurrQtyHistItems + 1;
    
    IF vn_CurrQtyHistItems > vn_MaxQtyHistItems
    THEN
      DELETE FROM reco_rstx_galvreq_hist
      WHERE cutsch_hist_id = vn_OldestHistId;
      DELETE FROM reco_rstx_punasg_hist
      WHERE cutsch_hist_id = vn_OldestHistId;
      DELETE FROM reco_rstx_punreq_hist
      WHERE cutsch_hist_id = vn_OldestHistId;
      DELETE FROM reco_rstx_punovg_hist
      WHERE cutsch_hist_id = vn_OldestHistId;
      DELETE FROM reco_rstx_punrun_hist
      WHERE cutsch_hist_id = vn_OldestHistId;
      DELETE FROM reco_rstx_cutasgv2_hist
      WHERE cutsch_hist_id = vn_OldestHistId;
      DELETE FROM reco_rstx_cutreqv2_hist
      WHERE cutsch_hist_id = vn_OldestHistId;
      DELETE FROM reco_rstx_cutovg_hist
      WHERE cutsch_hist_id = vn_OldestHistId;
      DELETE FROM reco_rstx_cutrun_hist
      WHERE cutsch_hist_id = vn_OldestHistId;
      DELETE FROM reco_rstx_runplac_hist
      WHERE cutsch_hist_id = vn_OldestHistId;
      DELETE FROM reco_rstx_daypktbin_hist
      WHERE cutsch_hist_id = vn_OldestHistId;
      DELETE FROM reco_rstx_daypkt_hist
      WHERE cutsch_hist_id = vn_OldestHistId;
      DELETE FROM reco_rstx_calday_hist
      WHERE cutsch_hist_id = vn_OldestHistId;
      DELETE FROM reco_rstx_originvqty_hist
      WHERE cutsch_hist_id = vn_OldestHistId;
      DELETE FROM reco_rstx_cutsch_hist
      WHERE cutsch_hist_id = vn_OldestHistId;
      DELETE FROM reco_rstx_userparam_hist
      WHERE cutsch_hist_id = vn_OldestHistId;
      
      vn_CurrQtyHistItems := vn_CurrQtyHistItems - 1;
    END IF;
  END;
  
  ---
  -- We have successfully calculated a cut/pun/galv schedule,
  -- and then placed it into the history tables.
  -- 
  -- Now we can clear/delete everything except for those history tables
  ---
  
  clear_existing_reqsandplans;
  
  -- We are done
  
  COMMIT;
  
  RETURN 'DONE';
END; -- run_cut_optimize
  
--------------------------------------------------------------------------------
-- rstx_cut_rpt
PROCEDURE rstx_cut_rpt
IS
  vn_TmpHistId number;
BEGIN
  SELECT MAX(cutsch_hist_id) INTO vn_TmpHistId FROM reco_rstx_cutsch_hist;
  
  IF vn_TmpHistId IS NULL
  THEN
    reco_web_functions.reset_sheet;
    reco_web_functions.table_attr := 'border="1" frame="border" rules="all"';
--    reco_web_functions.open_spreadsheet;
    reco_web_functions.open_spreadsheet('NODATE:reco_cut_schedule_sheet'); --Added by RS on 03/04/2026.
    reco_web_functions.col_span := 10;
    reco_web_functions.add_header_column(
      'Internal Error 2049 - History and Processing is Corrupted. Contact MIS.');
    reco_web_functions.print_header;
    reco_web_Functions.close_spreadsheet;
    RETURN;
  END IF;
  
  rstx_cut_rpt(TO_CHAR(vn_TmpHistId));
END;
  
--------------------------------------------------------------------------------
-- rstx_cut_rpt
PROCEDURE rstx_cut_rpt (pi_GivenHistId IN varchar2)
IS
  vr_Params reco_rstx_userparam_hist%ROWTYPE;
  
  vn_QtyColumnsInSpreadsheet number;
  
  vn_GivenHistId number;
  
  vd_FirstDate date;
  vd_SecondDate date;
  vd_ThirdDate date;
  vd_LastSafetyDate date;
  
BEGIN -- rstx_cut_rpt
  
  vn_GivenHistId := TO_NUMBER(pi_GivenHistId);
  
  BEGIN
    SELECT * INTO vr_Params
    FROM reco_rstx_userparam_hist WHERE cutsch_hist_id = vn_GivenHistId;
  EXCEPTION
    WHEN others
    THEN
      reco_web_functions.reset_sheet;
      reco_web_functions.table_attr := 'border="1" frame="border" rules="all"';
--      reco_web_functions.open_spreadsheet;
      reco_web_functions.open_spreadsheet('NODATE:reco_cut_schedule_sheet'); --Added by RS on 03/04/2026.
      reco_web_functions.col_span := 10;
      reco_web_functions.add_header_column(
        'Internal Error 2016 - Parameters Corrupted. Contact MIS.');
      reco_web_functions.print_header;
      reco_web_Functions.close_spreadsheet;
      RETURN;
  END;
  
  vn_QtyColumnsInSpreadsheet := 26;
  
  DECLARE
    vc_TmpOutMsg varchar2(1000);
  BEGIN
    
    vc_TmpOutMsg := check_rpt_daterange_valid(1);
    
    IF vc_TmpOutMsg != 'DONE'
    THEN
      reco_web_functions.reset_sheet;
      reco_web_functions.table_attr := 'border="1" frame="border" rules="all"';
--      reco_web_functions.open_spreadsheet;
      reco_web_functions.open_spreadsheet('NODATE:reco_cut_schedule_sheet'); --Added by RS on 03/04/2026.
      reco_web_functions.col_span := 10;
      reco_web_functions.add_header_column(
        'Internal Error 2064 - Invalid History / Date Tieback. Contact MIS.');
      reco_web_functions.print_header;
      reco_web_Functions.close_spreadsheet;
      RETURN;
    END IF;
    
    vc_TmpOutMsg := get_date_toshowin_rpt(vn_GivenHistId,
      FALSE,1,
      vr_Params.first_date_of_reqs,vr_Params.first_date_of_cutting,
      vd_FirstDate);
    
    IF vc_TmpOutMsg != 'DONE'
    THEN
      reco_web_functions.reset_sheet;
      reco_web_functions.table_attr := 'border="1" frame="border" rules="all"';
--      reco_web_functions.open_spreadsheet;
      reco_web_functions.open_spreadsheet('NODATE:reco_cut_schedule_sheet'); --Added by RS on 03/04/2026.
      reco_web_functions.col_span := 10;
      reco_web_functions.add_header_column(
        'Internal Error 2056 - Invalid History / Date Tieback. Contact MIS.');
      reco_web_functions.print_header;
      reco_web_Functions.close_spreadsheet;
      RETURN;
    END IF;
  END;
  
  DECLARE
    vc_TmpOutMsg varchar2(1000);
  BEGIN
    
    vc_TmpOutMsg := check_rpt_daterange_valid(2);
    
    IF vc_TmpOutMsg != 'DONE'
    THEN
      reco_web_functions.reset_sheet;
      reco_web_functions.table_attr := 'border="1" frame="border" rules="all"';
--      reco_web_functions.open_spreadsheet;
      reco_web_functions.open_spreadsheet('NODATE:reco_cut_schedule_sheet'); --Added by RS on 03/04/2026.
      reco_web_functions.col_span := 10;
      reco_web_functions.add_header_column(
        'Internal Error 2065 - Invalid History / Date Tieback. Contact MIS.');
      reco_web_functions.print_header;
      reco_web_Functions.close_spreadsheet;
      RETURN;
    END IF;
    
    vc_TmpOutMsg := get_date_toshowin_rpt(vn_GivenHistId,
      FALSE,2,
      vr_Params.first_date_of_reqs,vr_Params.first_date_of_cutting,
      vd_SecondDate);
    
    IF vc_TmpOutMsg != 'DONE'
    THEN
      reco_web_functions.reset_sheet;
      reco_web_functions.table_attr := 'border="1" frame="border" rules="all"';
--      reco_web_functions.open_spreadsheet;  
      reco_web_functions.open_spreadsheet('NODATE:reco_cut_schedule_sheet'); --Added by RS on 03/04/2026.
      reco_web_functions.col_span := 10;
      reco_web_functions.add_header_column(
        'Internal Error 2057 - Invalid History / Date Tieback. Contact MIS.');
      reco_web_functions.print_header;
      reco_web_Functions.close_spreadsheet;
      RETURN;
    END IF;
  END;
  
  DECLARE
    vc_TmpOutMsg varchar2(1000);
  BEGIN
    
    vc_TmpOutMsg := check_rpt_daterange_valid(3);
    
    IF vc_TmpOutMsg != 'DONE'
    THEN
      reco_web_functions.reset_sheet;
      reco_web_functions.table_attr := 'border="1" frame="border" rules="all"';
--      reco_web_functions.open_spreadsheet;
      reco_web_functions.open_spreadsheet('NODATE:reco_cut_schedule_sheet'); --Added by RS on 03/04/2026.
      reco_web_functions.col_span := 10;
      reco_web_functions.add_header_column(
        'Internal Error 2066 - Invalid History / Date Tieback. Contact MIS.');
      reco_web_functions.print_header;
      reco_web_Functions.close_spreadsheet;
      RETURN;
    END IF;
    
    vc_TmpOutMsg := get_date_toshowin_rpt(vn_GivenHistId,
      FALSE,3,
      vr_Params.first_date_of_reqs,vr_Params.first_date_of_cutting,
      vd_ThirdDate);
    
    IF vc_TmpOutMsg != 'DONE'
    THEN
      reco_web_functions.reset_sheet;
      reco_web_functions.table_attr := 'border="1" frame="border" rules="all"';
--      reco_web_functions.open_spreadsheet;
      reco_web_functions.open_spreadsheet('NODATE:reco_cut_schedule_sheet'); --Added by RS on 03/04/2026.
      reco_web_functions.col_span := 10;
      reco_web_functions.add_header_column(
        'Internal Error 2058 - Invalid History / Date Tieback. Contact MIS.');
      reco_web_functions.print_header;
      reco_web_Functions.close_spreadsheet;
      RETURN;
    END IF;
  END;
  
  DECLARE
    vc_TmpOutMsg varchar2(1000);
  BEGIN
    
    vc_TmpOutMsg := check_rpt_daterange_valid(vr_Params.safety_days_out + 1);
    
    IF vc_TmpOutMsg != 'DONE'
    THEN
      reco_web_functions.reset_sheet;
      reco_web_functions.table_attr := 'border="1" frame="border" rules="all"';
--      reco_web_functions.open_spreadsheet;
      reco_web_functions.open_spreadsheet('NODATE:reco_cut_schedule_sheet'); --Added by RS on 03/04/2026.
      reco_web_functions.col_span := 10;
      reco_web_functions.add_header_column(
        'Internal Error 2067 - Invalid History / Date Tieback. Contact MIS.');
      reco_web_functions.print_header;
      reco_web_Functions.close_spreadsheet;
      RETURN;
    END IF;
    
    vc_TmpOutMsg := get_date_toshowin_rpt(vn_GivenHistId,
      FALSE,vr_Params.safety_days_out + 1,
      vr_Params.first_date_of_reqs,vr_Params.first_date_of_cutting,
      vd_LastSafetyDate);
    
    IF vc_TmpOutMsg != 'DONE'
    THEN
      reco_web_functions.reset_sheet;
      reco_web_functions.table_attr := 'border="1" frame="border" rules="all"';
--      reco_web_functions.open_spreadsheet;
      reco_web_functions.open_spreadsheet('NODATE:reco_cut_schedule_sheet'); --Added by RS on 03/04/2026.
      reco_web_functions.col_span := 10;
      reco_web_functions.add_header_column(
        'Internal Error 2059 - Invalid History / Date Tieback. Contact MIS.');
      reco_web_functions.print_header;
      reco_web_Functions.close_spreadsheet;
      RETURN;
    END IF;
  END;
  
  ---
  -- Prepare spreadsheet
  ---
  
  reco_web_functions.reset_sheet;
  reco_web_functions.table_attr := 'border="1" frame="border" rules="all"';
--  reco_web_functions.open_spreadsheet;
  reco_web_functions.open_spreadsheet('NODATE:reco_cut_schedule_sheet'); --Added by RS on 03/04/2026.
  
  ---
  -- Print history info if needed
  ---
  
  DECLARE
    vn_MaxHist number;
    vc_TmpHistText reco_rstx_cutsch_hist.runname%TYPE;
  BEGIN
    SELECT MAX(cutsch_hist_id) INTO vn_MaxHist FROM reco_rstx_cutsch_hist;
    
    IF vn_GivenHistId != vn_MaxHist
    THEN
      SELECT runname INTO vc_TmpHistText
      FROM reco_rstx_cutsch_hist WHERE cutsch_hist_id = vn_GivenHistId;
  
      reco_web_functions.clear_headers;
  
      reco_web_functions.col_span := vn_QtyColumnsInSpreadsheet;
      reco_web_functions.add_header_column(
        'Cut Schedule History - '||vc_TmpHistText);
      reco_web_functions.print_header;
    END IF;
  END;
  
  ---
  -- Print main header
  ---
  
  reco_web_functions.clear_headers;
  
  reco_web_functions.col_span := vn_QtyColumnsInSpreadsheet;
  reco_web_functions.add_header_column('RSTX Cut Schedule');
  reco_web_functions.print_header;
  
  ---
  -- Print the Part-Exceptions note
  -- 
  -- Example:
  -- : Demanded Part Types that were invalidated in inventory
  -- : Demanded Parts with length <= min_length
  -- : Demanded Parts with length >= max_length
  ---
  
  DECLARE
    CURSOR cur_InvalidTypeParts
    IS
      SELECT  DISTINCT roiq.segment1
      FROM  reco_truck rs,
            reco_truckstop_parts rsp,
            apps.mtl_system_items_b_kfv msib,
            reco_rstx_originvqty_hist roiq
      WHERE   rs.truck_id = rsp.stop_truck_id
      AND     rsp.part_id = msib.inventory_item_id
      AND     msib.segment1 = roiq.segment1 AND msib.organization_id = 0
      AND     rs.truck_status IN ('A','H','B')
      AND     rsp.orig_subinventory_code IN ('RSTX')
      AND     NVL(rsp.quantity,0) > 0
      AND     rs.truck_date >= vr_Params.first_date_of_reqs
      AND     NOT EXISTS (SELECT 'Y'
                          FROM reco_rstx_originvqty_hist subQ
                          WHERE subQ.thetype = roiq.thetype
                          AND subQ.inventory_item_id IS NOT NULL
                          AND subQ.cutsch_hist_id = vn_GivenHistId)
      AND     roiq.cutsch_hist_id = vn_GivenHistId
      ORDER BY roiq.segment1;
    
    CURSOR cur_InvalidPartLens
    IS
      SELECT  DISTINCT roiq.segment1
      FROM  reco_truck rs,
            reco_truckstop_parts rsp,
            apps.mtl_system_items_b_kfv msib,
            reco_rstx_originvqty_hist roiq
      WHERE   rs.truck_id = rsp.stop_truck_id
      AND     rsp.part_id = msib.inventory_item_id AND msib.organizatioN_id = 0
      AND     msib.segment1 = roiq.segment1
      AND     rs.truck_status IN ('A','H','B')
      AND     rsp.orig_subinventory_code IN ('RSTX')
      AND     NVL(rsp.quantity,0) > 0
      AND     rs.truck_date >= vr_Params.first_date_of_reqs
      AND     EXISTS (SELECT 'Y'
                      FROM reco_rstx_originvqty_hist subQ
                      WHERE subQ.thetype = roiq.thetype
                      AND subQ.numlength = roiq.numlength
                      AND subQ.inventory_item_id IS NULL
                      AND subQ.category_set_id != nCSetR
                      AND (subQ.numlength < vr_Params.min_cut_allowed
                            OR subQ.numlength > vr_Params.max_cut_allowed)
                      AND subQ.cutsch_hist_id = vn_GivenHistId)
      AND     roiq.cutsch_hist_id = vn_GivenHistId
      ORDER BY roiq.segment1;
    
    vn_QtyExceptionsTyp number;
    vn_QtyExceptionsLen number;
    vc_Exception1Text varchar2(1000);
    vc_Exception2Text varchar2(1000);
  BEGIN
    vn_QtyExceptionsTyp := 0;
    vc_Exception1Text := '';
    
    FOR rec_InvalidTypeParts IN cur_InvalidTypeParts
    LOOP
      IF vn_QtyExceptionsTyp = 0
      THEN vc_Exception1Text := 'Exceptions - Part Type has errors (';
      ELSIF vn_QtyExceptionsTyp > 0
      THEN vc_Exception1Text := vc_Exception1Text||',';
      END IF;
      
      vc_Exception1Text := vc_Exception1Text||rec_InvalidTypeParts.segment1;
      
      vn_QtyExceptionsTyp := vn_QtyExceptionsTyp + 1;
      
      IF vn_QtyExceptionsTyp = 3 THEN exit; END IF;
    END LOOP;
    
    IF vn_QtyExceptionsTyp > 0
    THEN vc_Exception1Text := vc_Exception1Text||')';
    END IF;
    
    vn_QtyExceptionsLen := 0;
    vc_Exception2Text := '';
    
    FOR rec_InvalidPartLens IN cur_InvalidPartLens
    LOOP
      IF vn_QtyExceptionsLen = 0
      THEN vc_Exception2Text := 'Exceptions - Parts are not cut (';
      ELSIF vn_QtyExceptionsLen > 0
      THEN vc_Exception2Text := vc_Exception2Text||',';
      END IF;
      
      vc_Exception2Text := vc_Exception2Text||rec_InvalidPartLens.segment1;
      
      vn_QtyExceptionsLen := vn_QtyExceptionsLen + 1;
      
      IF vn_QtyExceptionsLen = 3 THEN exit; END IF;
    END LOOP;
    
    IF vn_QtyExceptionsLen > 0
    THEN vc_Exception2Text := vc_Exception2Text||')';
    END IF;
    
    IF vn_QtyExceptionsTyp > 0 OR vn_QtyExceptionsLen > 0
    THEN
      reco_web_functions.clear_headers;
      reco_web_functions.col_span  := vn_QtyColumnsInSpreadsheet;
      reco_web_functions.cell_attr := '';
      reco_web_functions.add_header_column(' ');
      reco_web_functions.print_header;
      
      IF vn_QtyExceptionsTyp > 0
      THEN
        reco_web_functions.clear_headers;
        reco_web_functions.col_span  := vn_QtyColumnsInSpreadsheet;
        reco_web_functions.cell_attr := '';
        reco_web_functions.add_header_column(vc_Exception1Text);
        reco_web_functions.print_header;
      
        reco_web_functions.clear_headers;
        reco_web_functions.col_span  := vn_QtyColumnsInSpreadsheet;
        reco_web_functions.cell_attr := '';
        reco_web_functions.add_header_column(
          'Part type has incorrect setup in Oracle, so it was not cut.');
        reco_web_functions.print_header;
      END IF;
      
      IF vn_QtyExceptionsLen > 0
      THEN
        reco_web_functions.clear_headers;
        reco_web_functions.col_span  := vn_QtyColumnsInSpreadsheet;
        reco_web_functions.cell_attr := '';
        reco_web_functions.add_header_column(vc_Exception2Text);
        reco_web_functions.print_header;
        
        reco_web_functions.clear_headers;
        reco_web_functions.col_span  := vn_QtyColumnsInSpreadsheet;
        reco_web_functions.cell_attr := '';
        reco_web_functions.add_header_column(
          'You can automate these parts by change Min/Max Cut');
        reco_web_functions.print_header;
      END IF;
    END IF;
  END;
  
  ---
  -- Print the Unsatisfied-PartType note
  -- 
  -- The parts made it into reco_rstx_cutreqv2_hist, but they were
  -- not satisfied (e.g. no bins were assigned for 506 type)
  -- 
  -- Examples:
  -- : We have a 506 part due within safety_days_out,
  --   but there were no days/pockets available to cut it
  --   (Note: This does not show parts that have
  --          bad Inventory Settings, because that does not
  --          affect the actual cutting/punching schedule
  --          (it works around the bad parts, based on partname).
  --          So do not expect this to show parts with
  --          inventory_item_id of null in reco_rstx_originvqty_hist)
  ---
  
  DECLARE
    CURSOR cur_UnfilledSpecials
    IS
      SELECT  DISTINCT cutreq.reqtype
      FROM  reco_rstx_cutreqv2_hist cutreq
      WHERE   NOT EXISTS (SELECT 1
                          FROM reco_rstx_cutasgv2_hist subasg
                          WHERE subasg.cutreq_id = cutreq.cutreq_id
                          AND subasg.cutsch_hist_id = vn_GivenHistId)
      AND     cutreq.reqdate <= vd_LastSafetyDate
      AND     cutreq.reqtype NOT IN ( '504','506')
      AND     cutreq.cutsch_hist_id = vn_GivenHistId;
    
    vc_FirstType reco_rstx_cutreqv2_hist.reqtype%TYPE;
    vc_SecondType reco_rstx_cutreqv2_hist.reqtype%TYPE;
  BEGIN
    
    vc_FirstType := NULL;
    vc_SecondType := NULL;
    
    OPEN cur_UnfilledSpecials;
    
    FETCH cur_UnfilledSpecials INTO vc_FirstType;
    IF cur_UnfilledSpecials%FOUND
    THEN
      FETCH cur_UnfilledSpecials INTO vc_SecondType;
      IF cur_UnfilledSpecials%NOTFOUND THEN vc_SecondType := NULL; END IF;
      
    ELSIF cur_UnfilledSpecials%NOTFOUND
    THEN vc_FirstType := NULL; vc_SecondType := NULL;
    END IF;
    
    CLOSE cur_UnfilledSpecials;
    
    IF vc_FirstType IS NOT NULL
    THEN
      reco_web_functions.clear_headers;
      reco_web_functions.col_span  := vn_QtyColumnsInSpreadsheet;
      reco_web_functions.cell_attr := '';
      reco_web_functions.add_header_column(' ');
      reco_web_functions.print_header;
      
      reco_web_functions.clear_headers;
      reco_web_functions.col_span  := vn_QtyColumnsInSpreadsheet;
      reco_web_functions.cell_attr := '';
      IF vc_SecondType IS NULL
      THEN
        reco_web_functions.add_header_column(
          'Some '||vc_FirstType||'mm strips were not cut');
      ELSIF vc_SecondType IS NOT NULL
      THEN
        reco_web_functions.add_header_column(
          'Some '||vc_FirstType||'mm/'||vc_SecondType||
          'mm strips were not cut');
      END IF;
      reco_web_functions.print_header;
      
      reco_web_functions.clear_headers;
      reco_web_functions.col_span  := vn_QtyColumnsInSpreadsheet;
      reco_web_functions.cell_attr := '';
      reco_web_functions.add_header_column(
        'You need to budget more pockets for '
        ||vc_FirstType||'mm strips in Oracle');
      reco_web_functions.print_header;
    END IF;
  END;
  
  ---
  -- Print the requirements that were ignored/missed due to length
  -- 
  -- The parts did Not make it into reco_rstx_cutreqv2_hist.
  -- The parts were ignored because the length-of-part is outside
  -- of the user's chosen parameters
  -- 
  -- Examples:
  -- : We have a 504 part due within safety_days_out,
  --   but its length is 3' and we don't automate 3' bars
  --   (based on reco_rstx_userparam_hist)
  ---
  
  DECLARE
    CURSOR cur_Ignored504 (pi_LastDayToFindBadShips IN date)
    IS
      -- Note: You have to link through mtl_system_items_b_kfv
      --       to get the inventory_item_id because the
      --       roiq table doesn't keep the inventory_item_id
      --       for errored parts
      SELECT  subQFirstShipId.shipment_id,
              rs.truck_date shipment_date,
              rs.tracking_number,
              subQFirstShipId.segment1,
              SUM(rsp.quantity) quantity
      FROM  reco_truck rs,
            reco_truckstop_parts_v rsp,
            apps.mtl_system_items_b_kfv msib,
            (
              SELECT  subroiq.segment1,
                      MIN(subrsp.shipment_id) shipment_id
              FROM  reco_rstx_originvqty_hist subroiq,
                    apps.mtl_system_items_b_kfv submsib,
                    reco_truckstop_parts_v subrsp,
                    reco_truck subrs
              WHERE   subroiq.segment1 = submsib.segment1
              AND     submsib.inventory_item_id = subrsp.part_id AND submsib.organization_id = 0
              AND     subrsp.stop_truck_id = subrs.truck_id
              AND     subroiq.cutsch_hist_id = vn_GivenHistId
              AND     subroiq.inventory_item_id IS NULL
              AND     subroiq.category_set_id IN (nCSetN,nCSetB,nCSetG)
              AND     subroiq.thetype IN ( '504','506')
              AND     subrs.truck_date IN
                      (
                        SELECT  MIN(l2rs.truck_date) mindate
                        FROM  apps.mtl_system_items_b_kfv l2msib,
                              reco_truckstop_parts l2rsp,
                              reco_truck l2rs
                        WHERE   subroiq.segment1 = l2msib.segment1 AND l2msib.organization_id = 0
                        AND     l2msib.inventory_item_id = l2rsp.part_id
                        AND     l2rsp.stop_truck_id = l2rs.truck_id
                        AND     NVL(l2rsp.quantity,0) > 0
                        AND     l2rsp.orig_subinventory_code
                                      IN ('RSTX')
                        AND     l2rs.truck_status
                                      IN ('A','H','B')
                        AND     l2rs.truck_date
                                      >= vr_Params.first_date_of_reqs
                        AND     l2rs.truck_date
                                      <= pi_LastDayToFindBadShips
                      )
              GROUP BY  subroiq.segment1
            ) subQFirstShipId
      WHERE   subQFirstShipId.segment1 = msib.segment1
      AND     msib.inventory_item_id = rsp.part_id AND msib.organization_id = 0
      AND     rsp.shipment_id = subQFirstShipId.shipment_id
      AND     rsp.orig_subinventory_code IN ('RSTX')
      AND     NVL(rsp.quantity,0) > 0
      AND     rsp.stop_truck_id = rs.truck_id
      GROUP BY  subQFirstShipId.shipment_id,
                rs.truck_date,
                rs.tracking_number,
                subQFirstShipId.segment1
      ORDER BY    rs.truck_date,
                  subQFirstShipId.segment1;
    
    vd_LastDateToDetect date;
    
    vn_Qty504MsgsShown number;
    --vn_QtyOtherMsgsShown number;
  BEGIN
      -- Note#2: We use rare_length_days_out parameter
      --         in a non-standard fashion here.
      --         It works fine, but "rare_length_days_out"
      --         is only supposed to be used for rare/special
      --         lengths, and NOT for length<MIN or length>MAX
      --         pieces. This works, but it is not best design
    
    vn_Qty504MsgsShown := 0;
    
    SELECT thedate
    INTO vd_LastDateToDetect
    FROM
    (
      SELECT ROWNUM therownum, thedate
      FROM
      (
        SELECT calday.thedate
        FROM reco_rstx_calday calday -- Good:see get_date_toshowin_rpt description
        WHERE calday.thedate > vr_Params.first_date_of_cutting
        AND calday.is_production_allowed = 'Y'
        ORDER BY calday.thedate
      )
    )
    WHERE therownum = vr_Params.rare_length_days_out;
    
    FOR rec_Ignored504 IN cur_Ignored504 (vd_LastDateToDetect)
    LOOP
      IF vn_Qty504MsgsShown = 0
      THEN
        reco_web_functions.clear_headers;
        reco_web_functions.col_span  := vn_QtyColumnsInSpreadsheet;
        reco_web_functions.cell_attr := '';
        reco_web_functions.add_header_column(' ');
        reco_web_functions.print_header;
      END IF;
      
      reco_web_functions.clear_headers;
      IF vn_QtyColumnsInSpreadsheet > 16
      THEN
        reco_web_functions.col_span  := 2;
        reco_web_functions.cell_attr := ' <font color=RED';
        reco_web_functions.add_header_column('Warning');
        reco_web_functions.col_span  := 8;
        reco_web_functions.cell_attr := '';
        reco_web_functions.add_header_column(
          'Part '||rec_Ignored504.segment1||' is scheduled to go '||
          TO_CHAR(rec_Ignored504.shipment_date,'DD-MON')||' on shipment:');
        reco_web_functions.col_span  := 4;
        reco_web_functions.cell_attr := '';
        reco_web_functions.add_header_column(
          '<A HREF="reco_web_info.display_shipment?p_shipment_id='||
          TO_CHAR(rec_Ignored504.shipment_id)||'" target="new">'||
          rec_Ignored504.tracking_number||'</A>');
        reco_web_functions.col_span  := vn_QtyColumnsInSpreadsheet - 14;
        reco_web_functions.cell_attr := '';
        reco_web_functions.add_header_column(' ');
      ELSIF vn_QtyColumnsInSpreadsheet <= 16
      THEN
        reco_web_functions.col_span  := vn_QtyColumnsInSpreadsheet;
        reco_web_functions.cell_attr := '';
        reco_web_functions.add_header_column(
          'Warning: Part '||rec_Ignored504.segment1||
          ' was not cut. But it is scheduled for shipment '||
          '<A HREF="reco_web_info.display_shipment?p_shipment_id='||
          TO_CHAR(rec_Ignored504.shipment_id)||'" target="new">'||
          rec_Ignored504.tracking_number||'</A> on '||
          TO_CHAR(rec_Ignored504.shipment_date,'DD-MON'));
      END IF;
      reco_web_functions.print_header;
      
      vn_Qty504MsgsShown := vn_Qty504MsgsShown + 1;
    END LOOP;
    
    --vn_QtyOtherMsgsShown := 0;
    --
    --for rec_IgnoredOther in cur_IgnoredOther
    --loop
    --  if vn_Qty504MsgsShown = 0 and vn_QtyOtherMsgsShown = 0
    --  then
    --    reco_web_functions.clear_headers;
    --    reco_web_functions.col_span  := vn_QtyColumnsInSpreadsheet;
    --    reco_web_functions.cell_attr := '';
    --    reco_web_functions.add_header_column(' ');
    --    reco_web_functions.print_header;
    --  end if;
    --  
    -- reco_web_functions.clear_headers;
    -- if vn_QtyColumnsInSpreadsheet > 16
    -- then
    --   reco_web_functions.col_span  := 2;
    --    reco_web_functions.cell_attr := '';
    --    reco_web_functions.add_header_column('Warning');
    --    reco_web_functions.col_span  := 8;
    --    reco_web_functions.cell_attr := '';
    --    reco_web_functions.add_header_column(
    --      'Part '||rec_IgnoredOther.segment1||' is scheduled to go '||
    --      to_char(rec_IgnoredOther.shipment_date,'DD-MON')||' on shipment:');
    --    reco_web_functions.col_span  := 4;
    --    reco_web_functions.cell_attr := '';
    --    reco_web_functions.add_header_column(
    --      '<A HREF="reco_web_info.display_shipment?p_shipment_id='||
    --      to_char(rec_IgnoredOther.shipment_id)||'" target="new">'||
    --      rec_IgnoredOther.tracking_number||'</A>');
    --    reco_web_functions.col_span  := vn_QtyColumnsInSpreadsheet - 14;
    --    reco_web_functions.cell_attr := '';
    --    reco_web_functions.add_header_column(' ');
    --  elsif vn_QtyColumnsInSpreadsheet <= 16
    --  then
    --    reco_web_functions.col_span  := vn_QtyColumnsInSpreadsheet;
    --    reco_web_functions.cell_attr := '';
    --    reco_web_functions.add_header_column(
    --      'Warning: Part '||rec_IgnoredOther.segment1||
    --      ' was not cut. But it is scheduled for shipment '||
    --      '<A HREF="reco_web_info.display_shipment?p_shipment_id='||
    --      to_char(rec_IgnoredOther.shipment_id)||'" target="new">'||
    --      rec_IgnoredOther.tracking_number||'</A> on '||
    --      to_char(rec_IgnoredOther.shipment_date,'DD-MON'));
    --  end if;
    --  reco_web_functions.print_header;
    --  
    --  if vn_QtyOtherMsgsShown >= 2
    --  then exit;
    --  end if;
    --  
    --  vn_QtyOtherMsgsShown := vn_QtyOtherMsgsShown + 1;
    --end loop;
  END;
  
  ---
  -- Print two blank lines before we get to the schedule
  ---
  
  reco_web_functions.clear_headers;
  reco_web_functions.col_span  := vn_QtyColumnsInSpreadsheet;
  reco_web_functions.cell_attr := '';
  reco_web_functions.add_header_column(' ');
  reco_web_functions.print_header;
  
  reco_web_functions.clear_headers;
  reco_web_functions.col_span  := vn_QtyColumnsInSpreadsheet;
  reco_web_functions.cell_attr := '';
  reco_web_functions.add_header_column(' ');
  reco_web_functions.print_header;
  
  ---
  -- Print date header for each item
  ---
  
  reco_web_functions.clear_headers;
  reco_web_functions.col_span  := 8;
  reco_web_functions.cell_attr := '';
  --reco_web_functions.col_span  := '';
  --reco_web_functions.col_span := 1;
  --reco_web_functions.col_span := 4;
  --reco_web_functions.cell_attr := 'bgcolor = #FF0000';
  --reco_web_functions.cell_attr :=  ' <font color=RED';
  --reco_web_functions.cell_attr := 'bgcolor =#FFFFFF <font color=RED';
  reco_web_functions.add_header_column(
    'Date '||TO_CHAR(vd_FirstDate, 'DD-MON-YYYY'));
  reco_web_functions.col_span  := 1;
  reco_web_functions.cell_attr := '';
  reco_web_functions.add_header_column(' ');
  reco_web_functions.col_span  := 8;
  reco_web_functions.cell_attr := '';
  reco_web_functions.add_header_column(
    'Date '||TO_CHAR(vd_SecondDate, 'DD-MON-YYYY'));
  reco_web_functions.col_span  := 1;
  reco_web_functions.cell_attr := '';
  reco_web_functions.add_header_column(' ');
  reco_web_functions.col_span  := 8;
  reco_web_functions.cell_attr := '';
  reco_web_functions.add_header_column(
    'Date '||TO_CHAR(vd_ThirdDate, 'DD-MON-YYYY'));
  reco_web_functions.print_header;
  
  ---
  -- Calculate data lines and Print data lines
  ---
  
  DECLARE
    -- Actual Date/Pocket/Bin usage for a givenDate,
    -- ordered by pocket number and bin number
    CURSOR cur_PktBinInfo (givenDate IN date)
    IS
      SELECT  daypktbin.length_of_part,
              subQBinTotals.totqtystrips,
              daypktbin.last_machine_label,
              daypocket.parttype,
              subQFirstReqDate.thedate firstship,
              DECODE(NVL(subQFoundOvg.thebinid,-1),-1, 'N','Y') hasovg,
              daypocket.pocket_number,
              TO_NUMBER(SUBSTR(daypktbin.last_machine_label,1,
                          INSTR(daypktbin.last_machine_label,'-',1,1)-1)) binnum,
              subQThePunch.thepunch
      FROM  reco_rstx_calday_hist calday,
            reco_rstx_daypkt_hist daypocket,
            reco_rstx_daypktbin_hist daypktbin,
            reco_rstx_runplac_hist placement, -- Currently 1-to-1 w/ daypktbin
            reco_rstx_cutrun_hist cutrun, -- Current 1-to-1 with placement
            (
              SELECT day_pkt_bin_id, SUM(qty_placed) totqtystrips
              FROM reco_rstx_runplac_hist
              WHERE cutsch_hist_id = vn_GivenHistId
              GROUP BY day_pkt_bin_id
            ) subQBinTotals,
            (
              SELECT  placement.day_pkt_bin_id thebinid,
                      MIN(cutreq.reqdate) thedate
              FROM  reco_rstx_runplac_hist placement,
                    reco_rstx_cutrun_hist cutrun,
                    reco_rstx_cutasgv2_hist cutasg,
                    reco_rstx_cutreqv2_hist cutreq
              WHERE   placement.cutrun_id = cutrun.cutrun_id
              AND     cutrun.cutrun_id = cutasg.cutrun_id
              AND     cutasg.cutreq_id = cutreq.cutreq_id
              AND     placement.cutsch_hist_id = vn_GivenHistId
              AND     cutrun.cutsch_hist_id = vn_GivenHistId
              AND     cutasg.cutsch_hist_id = vn_GivenHistId
              AND     cutreq.cutsch_hist_id = vn_GivenHistId
              GROUP BY  placement.day_pkt_bin_id
            ) subQFirstReqDate,
            (
              SELECT  DISTINCT placement.day_pkt_bin_id thebinid
              FROM  reco_rstx_runplac_hist placement,
                    reco_rstx_cutrun_hist cutrun
              WHERE   placement.cutrun_id = cutrun.cutrun_id
              AND     EXISTS (SELECT 1
                              FROM reco_rstx_cutovg_hist subovg
                              WHERE subovg.cutrun_id = cutrun.cutrun_id
                              AND subovg.cutsch_hist_id = vn_GivenHistId)
              AND     placement.cutsch_hist_id = vn_GivenHistId
              AND     cutrun.cutsch_hist_id = vn_GivenHistId
            ) subQFoundOvg,
            (
              SELECT  DISTINCT -- Needed: One cutrun_id can hit Many reqs
                      subasg.cutrun_id,
                      subreq.reqpunch thepunch
              FROM  reco_rstx_cutasgv2_hist subasg,
                    reco_rstx_cutreqv2_hist subreq
              WHERE   subasg.cutreq_id = subreq.cutreq_id
              AND     subasg.cutsch_hist_id = vn_GivenHistId
              AND     subreq.cutsch_hist_id = vn_GivenHistId
            ) subQThePunch
      WHERE   givenDate = calday.thedate
      AND     calday.calday_id = daypocket.calday_id
      AND     daypocket.day_pocket_id = daypktbin.day_pocket_id
      AND     daypktbin.day_pkt_bin_id = placement.day_pkt_bin_id
      AND     placement.cutrun_id = cutrun.cutrun_id
      AND     cutrun.cutrun_id = subQThePunch.cutrun_id (+)
      AND     daypktbin.day_pkt_bin_id = subQBinTotals.day_pkt_bin_id (+)
      AND     daypktbin.day_pkt_bin_id = subQFirstReqDate.thebinid (+)
      AND     daypktbin.day_pkt_bin_id = subQFoundOvg.thebinid (+)
      AND     calday.cutsch_hist_id = vn_GivenHistId
      AND     daypocket.cutsch_hist_id = vn_GivenHistId
      AND     daypktbin.cutsch_hist_id = vn_GivenHistId
      AND     placement.cutsch_hist_id = vn_GivenHistId
      AND     cutrun.cutsch_hist_id = vn_GivenHistId
      ORDER BY  daypocket.pocket_number desc,
                TO_NUMBER(SUBSTR(daypktbin.last_machine_label,1,
                          INSTR(daypktbin.last_machine_label,'-',1,1)-1)) desc;
    
    TYPE coll_PktBinInfo IS TABLE OF cur_PktBinInfo%ROWTYPE;
    
    oTheActualUsage coll_PktBinInfo;
    -- Fetched, so don't initialize
    --oTheActualUsage coll_PktBinInfo := coll_PktBinInfo();
    nCtrActualUsage number;
    
    oThe1stDateData coll_PktBinInfo := coll_PktBinInfo();
                                      -- Initialize since not fetched
    nCtr1stDateData number;
    b1stLastPrintBlnk BOOLEAN;
    b1stLastPrintHdr BOOLEAN;
    b1stDidPrintNone BOOLEAN;
    
    oThe2ndDateData coll_PktBinInfo := coll_PktBinInfo();
                                      -- Initialize since not fetched
    nCtr2ndDateData number;
    b2ndLastPrintBlnk BOOLEAN;
    b2ndLastPrintHdr BOOLEAN;
    b2ndDidPrintNone BOOLEAN;
    
    oThe3rdDateData coll_PktBinInfo := coll_PktBinInfo();
                                      -- Initialize since not fetched
    nCtr3rdDateData number;
    b3rdLastPrintBlnk BOOLEAN;
    b3rdLastPrintHdr BOOLEAN;
    b3rdDidPrintNone BOOLEAN;
  BEGIN
    
    ---
    -- Calculate data lines
    ---
    
    OPEN cur_PktBinInfo(vd_FirstDate);
    FETCH cur_PktBinInfo BULK COLLECT INTO oTheActualUsage;
    CLOSE cur_PktBinInfo;
    
    nCtr1stDateData := NULL;
    b1stLastPrintBlnk := TRUE;
    b1stLastPrintHdr := FALSE;
    b1stDidPrintNone := FALSE;
    
    IF oTheActualUsage.count > 0
    THEN
      oThe1stDateData.extend(oTheActualUsage.count);
      FOR tmpCnt IN 1 .. oTheActualUsage.count
      LOOP oThe1stDateData(tmpCnt) := oTheActualUsage(tmpCnt);
      END LOOP;
      
      IF vr_Params.show_cutrpt_100incrs = 'Y'
      THEN
        nCtr1stDateData := 1;
        
        LOOP
          IF oThe1stDateData(nCtr1stDateData).totqtystrips > 100
          THEN
            oThe1stDateData.extend(1);
            oThe1stDateData(oThe1stDateData.count)
                  := oThe1stDateData(nCtr1stDateData);
            
            oThe1stDateData(nCtr1stDateData).totqtystrips := 100;
            
            oThe1stDateData(oThe1stDateData.count).totqtystrips
                  := oThe1stDateData(oThe1stDateData.count).totqtystrips - 100;
          END IF;
          
          IF nCtr1stDateData < oThe1stDateData.count
          THEN
            nCtr1stDateData := nCtr1stDateData + 1;
            CONTINUE;
          END IF;
          
          exit;
        END LOOP;
      END IF;
      
      -- Since records exist, then set this to 0 and not null (for the loop)
      nCtr1stDateData := 0;
    END IF;
    
    OPEN cur_PktBinInfo(vd_SecondDate);
    FETCH cur_PktBinInfo BULK COLLECT INTO oTheActualUsage;
    CLOSE cur_PktBinInfo;
    
    nCtr2ndDateData := NULL;
    b2ndLastPrintBlnk := TRUE;
    b2ndLastPrintHdr := FALSE;
    b2ndDidPrintNone := FALSE;
    
    IF oTheActualUsage.count > 0
    THEN
      oThe2ndDateData.extend(oTheActualUsage.count);
      FOR tmpCnt IN 1 .. oTheActualUsage.count
      LOOP oThe2ndDateData(tmpCnt) := oTheActualUsage(tmpCnt);
      END LOOP;
      
      IF vr_Params.show_cutrpt_100incrs = 'Y'
      THEN
        nCtr2ndDateData := 1;
        
        LOOP
          IF oThe2ndDateData(nCtr2ndDateData).totqtystrips > 100
          THEN
            oThe2ndDateData.extend(1);
            oThe2ndDateData(oThe2ndDateData.count)
                  := oThe2ndDateData(nCtr2ndDateData);
            
            oThe2ndDateData(nCtr2ndDateData).totqtystrips := 100;
            
            oThe2ndDateData(oThe2ndDateData.count).totqtystrips
                  := oThe2ndDateData(oThe2ndDateData.count).totqtystrips - 100;
          END IF;
          
          IF nCtr2ndDateData < oThe2ndDateData.count
          THEN
            nCtr2ndDateData := nCtr2ndDateData + 1;
            CONTINUE;
          END IF;
          
          exit;
        END LOOP;
      END IF;
      
      -- Since records exist, then set this to 0 and not null (for the loop)
      nCtr2ndDateData := 0;
    END IF;
    
    OPEN cur_PktBinInfo(vd_ThirdDate);
    FETCH cur_PktBinInfo BULK COLLECT INTO oTheActualUsage;
    CLOSE cur_PktBinInfo;
    
    nCtr3rdDateData := NULL;
    b3rdLastPrintBlnk := TRUE;
    b3rdLastPrintHdr := FALSE;
    b3rdDidPrintNone := FALSE;
    
    IF oTheActualUsage.count > 0
    THEN
      oThe3rdDateData.extend(oTheActualUsage.count);
      FOR tmpCnt IN 1 .. oTheActualUsage.count
      LOOP oThe3rdDateData(tmpCnt) := oTheActualUsage(tmpCnt);
      END LOOP;
      
      IF vr_Params.show_cutrpt_100incrs = 'Y'
      THEN
        nCtr3rdDateData := 1;
        
        LOOP
          IF oThe3rdDateData(nCtr3rdDateData).totqtystrips > 100
          THEN
            oThe3rdDateData.extend(1);
            oThe3rdDateData(oThe3rdDateData.count)
                  := oThe3rdDateData(nCtr3rdDateData);
            
            oThe3rdDateData(nCtr3rdDateData).totqtystrips := 100;
            
            oThe3rdDateData(oThe3rdDateData.count).totqtystrips
                  := oThe3rdDateData(oThe3rdDateData.count).totqtystrips - 100;
          END IF;
          
          IF nCtr3rdDateData < oThe3rdDateData.count
          THEN
            nCtr3rdDateData := nCtr3rdDateData + 1;
            CONTINUE;
          END IF;
          
          exit;
        END LOOP;
      END IF;
      
      -- Since records exist, then set this to 0 and not null (for the loop)
      nCtr3rdDateData := 0;
    END IF;
    
    ---
    -- Print data lines
    ---
    
    LOOP
      
      IF nCtr1stDateData IS NOT NULL
      THEN nCtr1stDateData := nCtr1stDateData + 1;
      END IF;
      
      IF oThe1stDateData.count = 0 AND b1stDidPrintNone = FALSE
      THEN
        reco_web_functions.col_span := 8;
        reco_web_functions.cell_attr := '';
        reco_web_functions.add_data_column(
          'No runs set for this day');
        
        b1stDidPrintNone := TRUE;
        b1stLastPrintBlnk := FALSE;
        b1stLastPrintHdr := FALSE;
        nCtr1stDateData := NULL;
      ELSIF nCtr1stDateData IS NULL
      OR nCtr1stDateData > oThe1stDateData.count
      THEN
        reco_web_functions.col_span := 1;
        reco_web_functions.cell_attr := '';
        reco_web_functions.add_data_column(' ');
        reco_web_functions.col_span := 1;
        reco_web_functions.cell_attr := '';
        reco_web_functions.add_data_column(' ');
        reco_web_functions.col_span := 1;
        reco_web_functions.cell_attr := '';
        reco_web_functions.add_data_column(' ');
        reco_web_functions.col_span := 1;
        reco_web_functions.cell_attr := '';
        reco_web_functions.add_data_column(' ');
        reco_web_functions.col_span := 1;
        reco_web_functions.cell_attr := '';
        reco_web_functions.add_data_column(' ');
        reco_web_functions.col_span := 1;
        reco_web_functions.cell_attr := '';
        reco_web_functions.add_data_column(' ');
        reco_web_functions.col_span := 1;
        reco_web_functions.cell_attr := '';
        reco_web_functions.add_data_column(' ');
        reco_web_functions.col_span := 1;
        reco_web_functions.cell_attr := '';
        reco_web_functions.add_data_column(' ');
        
        b1stLastPrintBlnk := FALSE;
        b1stLastPrintHdr := FALSE;
        nCtr1stDateData := NULL;
      ELSIF b1stLastPrintBlnk = TRUE
      THEN
        reco_web_functions.col_span := 1;
        reco_web_functions.cell_attr := '';
        reco_web_functions.add_data_column('Part');
        reco_web_functions.col_span := 1;
        reco_web_functions.cell_attr := '';
        reco_web_functions.add_data_column('Stop');
        reco_web_functions.col_span := 1;
        reco_web_functions.cell_attr := '';
        reco_web_functions.add_data_column('Bin');
        reco_web_functions.col_span := 1;
        reco_web_functions.cell_attr := '';
        reco_web_functions.add_data_column('Qty');
        reco_web_functions.col_span := 1;
        reco_web_functions.cell_attr := '';
        reco_web_functions.add_data_column('CUT');
        reco_web_functions.col_span := 1;
        reco_web_functions.cell_attr := '';
        reco_web_functions.add_data_column('LeftToCut');
        reco_web_functions.col_span := 1;
        reco_web_functions.cell_attr := '';
        reco_web_functions.add_data_column('BarTyp');
        reco_web_functions.col_span := 1;
        reco_web_functions.cell_attr := '';
        reco_web_functions.add_data_column('1st Ship');
        
        b1stLastPrintBlnk := FALSE;
        b1stLastPrintHdr := TRUE;
        nCtr1stDateData := nCtr1stDateData - 1;
      ELSIF nCtr1stDateData > 1
      AND oThe1stDateData(nCtr1stDateData).pocket_number !=
                oThe1stDateData(nCtr1stDateData-1).pocket_number
      AND b1stLastPrintHdr = FALSE
      THEN
        reco_web_functions.col_span := 8;
        reco_web_functions.cell_attr := '';
        reco_web_functions.add_data_column(' ');
        
        b1stLastPrintBlnk := TRUE;
        b1stLastPrintHdr := FALSE;
        nCtr1stDateData := nCtr1stDateData - 1;
      ELSE
        b1stLastPrintBlnk := FALSE;
        b1stLastPrintHdr := FALSE;
        
        DECLARE
          vc_TmpTxt varchar2(20);
        BEGIN
          vc_TmpTxt :=
            TO_CHAR(oThe1stDateData(nCtr1stDateData).length_of_part);
          IF oThe1stDateData(nCtr1stDateData).thepunch IS NOT NULL
          AND oThe1stDateData(nCtr1stDateData).thepunch != 'S'
          THEN
            vc_TmpTxt := vc_TmpTxt||
              ' ('||oThe1stDateData(nCtr1stDateData).thepunch||'P)';
          END IF;
          
          reco_web_functions.col_span := 1;
          reco_web_functions.cell_attr := '';
          reco_web_functions.add_data_column(vc_TmpTxt);
          
          vc_TmpTxt :=
            TO_CHAR(oThe1stDateData(nCtr1stDateData).binnum);
          
          reco_web_functions.col_span := 1;
          reco_web_functions.cell_attr := '';
          reco_web_functions.add_data_column(vc_TmpTxt);
          
          vc_TmpTxt :=
            TO_CHAR(oThe1stDateData(nCtr1stDateData).pocket_number);
          
          reco_web_functions.col_span := 1;
          reco_web_functions.cell_attr := '';
          reco_web_functions.add_data_column(vc_TmpTxt);
          
          vc_TmpTxt :=
            TO_CHAR(oThe1stDateData(nCtr1stDateData).totqtystrips);
          IF oThe1stDateData(nCtr1stDateData).hasovg = 'Y'
          AND oThe1stDateData(nCtr1stDateData).firstship IS NULL
          THEN vc_TmpTxt := vc_TmpTxt||'(I)';
          ELSIF oThe1stDateData(nCtr1stDateData).hasovg = 'Y'
          AND oThe1stDateData(nCtr1stDateData).firstship IS NOT NULL
          THEN vc_TmpTxt := vc_TmpTxt||'(i)';
          END IF;
          
          reco_web_functions.col_span := 1;
          reco_web_functions.cell_attr := '';
          reco_web_functions.add_data_column(vc_TmpTxt);
          
          vc_TmpTxt := ' ';
          
          reco_web_functions.col_span := 1;
          reco_web_functions.cell_attr := '';
          reco_web_functions.add_data_column(vc_TmpTxt);
          
          vc_TmpTxt := ' ';
          
          reco_web_functions.col_span := 1;
          reco_web_functions.cell_attr := '';
          reco_web_functions.add_data_column(vc_TmpTxt);
          
          vc_TmpTxt :=
            oThe1stDateData(nCtr1stDateData).parttype;
          
          reco_web_functions.col_span := 1;
          reco_web_functions.cell_attr := '';
          reco_web_functions.add_data_column(vc_TmpTxt);
          
          vc_TmpTxt := ' ';
          IF oThe1stDateData(nCtr1stDateData).firstship IS NOT NULL
          THEN vc_TmpTxt :=
                TO_CHAR(oThe1stDateData(nCtr1stDateData).firstship,'DD-MON');
          END IF;
          
          reco_web_functions.col_span := 1;
          reco_web_functions.cell_attr := '';
          reco_web_functions.add_data_column(vc_TmpTxt);
        END;
      END IF;
      
      reco_web_functions.col_span := 1;
      reco_web_functions.cell_attr := '';
      reco_web_functions.add_data_column(' ');
      
      IF nCtr2ndDateData IS NOT NULL
      THEN nCtr2ndDateData := nCtr2ndDateData + 1;
      END IF;
      
      IF oThe2ndDateData.count = 0 AND b2ndDidPrintNone = FALSE
      THEN
        reco_web_functions.col_span := 8;
        reco_web_functions.cell_attr := '';
        reco_web_functions.add_data_column(
          'No runs set for this day');
        
        b2ndDidPrintNone := TRUE;
        b2ndLastPrintBlnk := FALSE;
        b2ndLastPrintHdr := FALSE;
        nCtr2ndDateData := NULL;
      ELSIF nCtr2ndDateData IS NULL
      OR nCtr2ndDateData > oThe2ndDateData.count
      THEN
        reco_web_functions.col_span := 1;
        reco_web_functions.cell_attr := '';
        reco_web_functions.add_data_column(' ');
        reco_web_functions.col_span := 1;
        reco_web_functions.cell_attr := '';
        reco_web_functions.add_data_column(' ');
        reco_web_functions.col_span := 1;
        reco_web_functions.cell_attr := '';
        reco_web_functions.add_data_column(' ');
        reco_web_functions.col_span := 1;
        reco_web_functions.cell_attr := '';
        reco_web_functions.add_data_column(' ');
        reco_web_functions.col_span := 1;
        reco_web_functions.cell_attr := '';
        reco_web_functions.add_data_column(' ');
        reco_web_functions.col_span := 1;
        reco_web_functions.cell_attr := '';
        reco_web_functions.add_data_column(' ');
        reco_web_functions.col_span := 1;
        reco_web_functions.cell_attr := '';
        reco_web_functions.add_data_column(' ');
        reco_web_functions.col_span := 1;
        reco_web_functions.cell_attr := '';
        reco_web_functions.add_data_column(' ');
        
        b2ndLastPrintBlnk := FALSE;
        b2ndLastPrintHdr := FALSE;
        nCtr2ndDateData := NULL;
      ELSIF b2ndLastPrintBlnk = TRUE
      THEN
        reco_web_functions.col_span := 1;
        reco_web_functions.cell_attr := '';
        reco_web_functions.add_data_column('Part');
        reco_web_functions.col_span := 1;
        reco_web_functions.cell_attr := '';
        reco_web_functions.add_data_column('Stop');
        reco_web_functions.col_span := 1;
        reco_web_functions.cell_attr := '';
        reco_web_functions.add_data_column('Bin');
        reco_web_functions.col_span := 1;
        reco_web_functions.cell_attr := '';
        reco_web_functions.add_data_column('Qty');
        reco_web_functions.col_span := 1;
        reco_web_functions.cell_attr := '';
        reco_web_functions.add_data_column('CUT');
        reco_web_functions.col_span := 1;
        reco_web_functions.cell_attr := '';
        reco_web_functions.add_data_column('LeftToCut');
        reco_web_functions.col_span := 1;
        reco_web_functions.cell_attr := '';
        reco_web_functions.add_data_column('BarTyp');
        reco_web_functions.col_span := 1;
        reco_web_functions.cell_attr := '';
        reco_web_functions.add_data_column('1st Ship');
        
        b2ndLastPrintBlnk := FALSE;
        b2ndLastPrintHdr := TRUE;
        nCtr2ndDateData := nCtr2ndDateData - 1;
      ELSIF nCtr2ndDateData > 1
      AND oThe2ndDateData(nCtr2ndDateData).pocket_number !=
                oThe2ndDateData(nCtr2ndDateData-1).pocket_number
      AND b2ndLastPrintHdr = FALSE
      THEN
        reco_web_functions.col_span := 8;
        reco_web_functions.cell_attr := '';
        reco_web_functions.add_data_column(' ');
        
        b2ndLastPrintBlnk := TRUE;
        b2ndLastPrintHdr := FALSE;
        nCtr2ndDateData := nCtr2ndDateData - 1;
      ELSE
        b2ndLastPrintBlnk := FALSE;
        b2ndLastPrintHdr := FALSE;
        
        DECLARE
          vc_TmpTxt varchar2(20);
        BEGIN
          vc_TmpTxt :=
            TO_CHAR(oThe2ndDateData(nCtr2ndDateData).length_of_part);
          
          reco_web_functions.col_span := 1;
          reco_web_functions.cell_attr := '';
          reco_web_functions.add_data_column(vc_TmpTxt);
          
          vc_TmpTxt :=
            TO_CHAR(oThe2ndDateData(nCtr2ndDateData).binnum);
          
          reco_web_functions.col_span := 1;
          reco_web_functions.cell_attr := '';
          reco_web_functions.add_data_column(vc_TmpTxt);
          
          vc_TmpTxt :=
            TO_CHAR(oThe2ndDateData(nCtr2ndDateData).pocket_number);
          
          reco_web_functions.col_span := 1;
          reco_web_functions.cell_attr := '';
          reco_web_functions.add_data_column(vc_TmpTxt);
          
          vc_TmpTxt :=
            TO_CHAR(oThe2ndDateData(nCtr2ndDateData).totqtystrips);
          IF oThe2ndDateData(nCtr2ndDateData).hasovg = 'Y'
          AND oThe2ndDateData(nCtr2ndDateData).firstship IS NULL
          THEN vc_TmpTxt := vc_TmpTxt||'(I)';
          ELSIF oThe2ndDateData(nCtr2ndDateData).hasovg = 'Y'
          AND oThe2ndDateData(nCtr2ndDateData).firstship IS NOT NULL
          THEN vc_TmpTxt := vc_TmpTxt||'(i)';
          END IF;
          
          reco_web_functions.col_span := 1;
          reco_web_functions.cell_attr := '';
          reco_web_functions.add_data_column(vc_TmpTxt);
          
          vc_TmpTxt := ' ';
          
          reco_web_functions.col_span := 1;
          reco_web_functions.cell_attr := '';
          reco_web_functions.add_data_column(vc_TmpTxt);
          
          vc_TmpTxt := ' ';
          
          reco_web_functions.col_span := 1;
          reco_web_functions.cell_attr := '';
          reco_web_functions.add_data_column(vc_TmpTxt);
          
          vc_TmpTxt :=
            oThe2ndDateData(nCtr2ndDateData).parttype;
          
          reco_web_functions.col_span := 1;
          reco_web_functions.cell_attr := '';
          reco_web_functions.add_data_column(vc_TmpTxt);
          
          vc_TmpTxt := ' ';
          IF oThe2ndDateData(nCtr2ndDateData).firstship IS NOT NULL
          THEN vc_TmpTxt :=
                TO_CHAR(oThe2ndDateData(nCtr2ndDateData).firstship,'DD-MON');
          END IF;
          
          reco_web_functions.col_span := 1;
          reco_web_functions.cell_attr := '';
          reco_web_functions.add_data_column(vc_TmpTxt);
        END;
      END IF;
      
      reco_web_functions.col_span := 1;
      reco_web_functions.cell_attr := '';
      reco_web_functions.add_data_column(' ');
      
      IF nCtr3rdDateData IS NOT NULL
      THEN nCtr3rdDateData := nCtr3rdDateData + 1;
      END IF;
      
      IF oThe3rdDateData.count = 0 AND b3rdDidPrintNone = FALSE
      THEN
        reco_web_functions.col_span := 8;
        reco_web_functions.cell_attr := '';
        reco_web_functions.add_data_column(
          'No runs set for this day');
        
        b3rdDidPrintNone := TRUE;
        b3rdLastPrintBlnk := FALSE;
        b3rdLastPrintHdr := FALSE;
        nCtr3rdDateData := NULL;
      ELSIF nCtr3rdDateData IS NULL
      OR nCtr3rdDateData > oThe3rdDateData.count
      THEN
        reco_web_functions.col_span := 1;
        reco_web_functions.cell_attr := '';
        reco_web_functions.add_data_column(' ');
        reco_web_functions.col_span := 1;
        reco_web_functions.cell_attr := '';
        reco_web_functions.add_data_column(' ');
        reco_web_functions.col_span := 1;
        reco_web_functions.cell_attr := '';
        reco_web_functions.add_data_column(' ');
        reco_web_functions.col_span := 1;
        reco_web_functions.cell_attr := '';
        reco_web_functions.add_data_column(' ');
        reco_web_functions.col_span := 1;
        reco_web_functions.cell_attr := '';
        reco_web_functions.add_data_column(' ');
        reco_web_functions.col_span := 1;
        reco_web_functions.cell_attr := '';
        reco_web_functions.add_data_column(' ');
        reco_web_functions.col_span := 1;
        reco_web_functions.cell_attr := '';
        reco_web_functions.add_data_column(' ');
        reco_web_functions.col_span := 1;
        reco_web_functions.cell_attr := '';
        reco_web_functions.add_data_column(' ');
        
        b3rdLastPrintBlnk := FALSE;
        b3rdLastPrintHdr := FALSE;
        nCtr3rdDateData := NULL;
      ELSIF b3rdLastPrintBlnk = TRUE
      THEN
        reco_web_functions.col_span := 1;
        reco_web_functions.cell_attr := '';
        reco_web_functions.add_data_column('Part');
        reco_web_functions.col_span := 1;
        reco_web_functions.cell_attr := '';
        reco_web_functions.add_data_column('Stop');
        reco_web_functions.col_span := 1;
        reco_web_functions.cell_attr := '';
        reco_web_functions.add_data_column('Bin');
        reco_web_functions.col_span := 1;
        reco_web_functions.cell_attr := '';
        reco_web_functions.add_data_column('Qty');
        reco_web_functions.col_span := 1;
        reco_web_functions.cell_attr := '';
        reco_web_functions.add_data_column('CUT');
        reco_web_functions.col_span := 1;
        reco_web_functions.cell_attr := '';
        reco_web_functions.add_data_column('LeftToCut');
        reco_web_functions.col_span := 1;
        reco_web_functions.cell_attr := '';
        reco_web_functions.add_data_column('BarTyp');
        reco_web_functions.col_span := 1;
        reco_web_functions.cell_attr := '';
        reco_web_functions.add_data_column('1st Ship');
        
        b3rdLastPrintBlnk := FALSE;
        b3rdLastPrintHdr := TRUE;
        nCtr3rdDateData := nCtr3rdDateData - 1;
      ELSIF nCtr3rdDateData > 1
      AND oThe3rdDateData(nCtr3rdDateData).pocket_number !=
                oThe3rdDateData(nCtr3rdDateData-1).pocket_number
      AND b3rdLastPrintHdr = FALSE
      THEN
        reco_web_functions.col_span := 8;
        reco_web_functions.cell_attr := '';
        reco_web_functions.add_data_column(' ');
        
        b3rdLastPrintBlnk := TRUE;
        b3rdLastPrintHdr := FALSE;
        nCtr3rdDateData := nCtr3rdDateData - 1;
      ELSE
        b3rdLastPrintBlnk := FALSE;
        b3rdLastPrintHdr := FALSE;
        
        DECLARE
          vc_TmpTxt varchar2(20);
        BEGIN
          vc_TmpTxt :=
            TO_CHAR(oThe3rdDateData(nCtr3rdDateData).length_of_part);
          
          reco_web_functions.col_span := 1;
          reco_web_functions.cell_attr := '';
          reco_web_functions.add_data_column(vc_TmpTxt);
          
          vc_TmpTxt :=
            TO_CHAR(oThe3rdDateData(nCtr3rdDateData).binnum);
          
          reco_web_functions.col_span := 1;
          reco_web_functions.cell_attr := '';
          reco_web_functions.add_data_column(vc_TmpTxt);
          
          vc_TmpTxt :=
            TO_CHAR(oThe3rdDateData(nCtr3rdDateData).pocket_number);
          
          reco_web_functions.col_span := 1;
          reco_web_functions.cell_attr := '';
          reco_web_functions.add_data_column(vc_TmpTxt);
          
          vc_TmpTxt :=
            TO_CHAR(oThe3rdDateData(nCtr3rdDateData).totqtystrips);
          IF oThe3rdDateData(nCtr3rdDateData).hasovg = 'Y'
          AND oThe3rdDateData(nCtr3rdDateData).firstship IS NULL
          THEN vc_TmpTxt := vc_TmpTxt||'(I)';
          ELSIF oThe3rdDateData(nCtr3rdDateData).hasovg = 'Y'
          AND oThe3rdDateData(nCtr3rdDateData).firstship IS NOT NULL
          THEN vc_TmpTxt := vc_TmpTxt||'(i)';
          END IF;
          
          reco_web_functions.col_span := 1;
          reco_web_functions.cell_attr := '';
          reco_web_functions.add_data_column(vc_TmpTxt);
          
          vc_TmpTxt := ' ';
          
          reco_web_functions.col_span := 1;
          reco_web_functions.cell_attr := '';
          reco_web_functions.add_data_column(vc_TmpTxt);
          
          vc_TmpTxt := ' ';
          
          reco_web_functions.col_span := 1;
          reco_web_functions.cell_attr := '';
          reco_web_functions.add_data_column(vc_TmpTxt);
          
          vc_TmpTxt :=
            oThe3rdDateData(nCtr3rdDateData).parttype;
          
          reco_web_functions.col_span := 1;
          reco_web_functions.cell_attr := '';
          reco_web_functions.add_data_column(vc_TmpTxt);
          
          vc_TmpTxt := ' ';
          IF oThe3rdDateData(nCtr3rdDateData).firstship IS NOT NULL
          THEN vc_TmpTxt :=
                TO_CHAR(oThe3rdDateData(nCtr3rdDateData).firstship,'DD-MON');
          END IF;
          
          reco_web_functions.col_span := 1;
          reco_web_functions.cell_attr := '';
          reco_web_functions.add_data_column(vc_TmpTxt);
        END;
      END IF;
      
      reco_web_functions.print_datarow;
      
      IF  nCtr1stDateData IS NULL
      AND nCtr2ndDateData IS NULL
      AND nCtr3rdDateData IS NULL
      THEN exit;
      END IF;
    END LOOP;
  END;
  
  ---
  -- Add some spacer at bottom
  ---
  
  reco_web_functions.col_span := 1;
  reco_web_functions.cell_attr := '';
  reco_web_functions.add_data_column(' ');
  reco_web_functions.col_span := 1;
  reco_web_functions.cell_attr := '';
  reco_web_functions.add_data_column(' ');
  reco_web_functions.col_span := 1;
  reco_web_functions.cell_attr := '';
  reco_web_functions.add_data_column(' ');
  reco_web_functions.col_span := 1;
  reco_web_functions.cell_attr := '';
  reco_web_functions.add_data_column(' ');
  reco_web_functions.col_span := 1;
  reco_web_functions.cell_attr := '';
  reco_web_functions.add_data_column('--------');
  reco_web_functions.col_span := 1;
  reco_web_functions.cell_attr := '';
  reco_web_functions.add_data_column('--------');
  reco_web_functions.col_span := 1;
  reco_web_functions.cell_attr := '';
  reco_web_functions.add_data_column(' ');
  reco_web_functions.col_span := 1;
  reco_web_functions.cell_attr := '';
  reco_web_functions.add_data_column(' ');
  reco_web_functions.col_span := 1;
  reco_web_functions.cell_attr := '';
  reco_web_functions.add_data_column('----');
  reco_web_functions.col_span := 1;
  reco_web_functions.cell_attr := '';
  reco_web_functions.add_data_column(' ');
  reco_web_functions.col_span := 1;
  reco_web_functions.cell_attr := '';
  reco_web_functions.add_data_column(' ');
  reco_web_functions.col_span := 1;
  reco_web_functions.cell_attr := '';
  reco_web_functions.add_data_column(' ');
  reco_web_functions.col_span := 1;
  reco_web_functions.cell_attr := '';
  reco_web_functions.add_data_column(' ');
  reco_web_functions.col_span := 1;
  reco_web_functions.cell_attr := '';
  reco_web_functions.add_data_column('--------');
  reco_web_functions.col_span := 1;
  reco_web_functions.cell_attr := '';
  reco_web_functions.add_data_column('--------');
  reco_web_functions.col_span := 1;
  reco_web_functions.cell_attr := '';
  reco_web_functions.add_data_column(' ');
  reco_web_functions.col_span := 1;
  reco_web_functions.cell_attr := '';
  reco_web_functions.add_data_column(' ');
  reco_web_functions.col_span := 1;
  reco_web_functions.cell_attr := '';
  reco_web_functions.add_data_column('----');
  reco_web_functions.col_span := 1;
  reco_web_functions.cell_attr := '';
  reco_web_functions.add_data_column(' ');
  reco_web_functions.col_span := 1;
  reco_web_functions.cell_attr := '';
  reco_web_functions.add_data_column(' ');
  reco_web_functions.col_span := 1;
  reco_web_functions.cell_attr := '';
  reco_web_functions.add_data_column(' ');
  reco_web_functions.col_span := 1;
  reco_web_functions.cell_attr := '';
  reco_web_functions.add_data_column(' ');
  reco_web_functions.col_span := 1;
  reco_web_functions.cell_attr := '';
  reco_web_functions.add_data_column('--------');
  reco_web_functions.col_span := 1;
  reco_web_functions.cell_attr := '';
  reco_web_functions.add_data_column('--------');
  reco_web_functions.col_span := 1;
  reco_web_functions.cell_attr := '';
  reco_web_functions.add_data_column(' ');
  reco_web_functions.col_span := 1;
  reco_web_functions.cell_attr := '';
  reco_web_functions.add_data_column(' ');
  
  reco_web_functions.print_datarow;
  
  ---
  -- Close spreadsheet
  ---
  
  reco_web_Functions.close_spreadsheet;
  
EXCEPTION
 WHEN others
 THEN
   htp.tableclose;
   htp.print('Report Exception Condition:'||sqlerrm|| -- CONTINUE HERE ADD TO OTHER FUNCTS
            ' Date:'||TO_CHAR(SYSDATE,'DD-MON-YYYY'));
   htp.htmlClose;
END; -- rstx_cut_rpt

--------------------------------------------------------------------------------
-- rstx_punchplanning_rpt
PROCEDURE rstx_punchplanning_rpt
IS
  vn_TmpHistId number;
BEGIN
  SELECT MAX(cutsch_hist_id) INTO vn_TmpHistId FROM reco_rstx_cutsch_hist;
  
  IF vn_TmpHistId IS NULL
  THEN
    reco_web_functions.reset_sheet;
    reco_web_functions.table_attr := 'border="1" frame="border" rules="all"';
--    reco_web_functions.open_spreadsheet;
    reco_web_functions.open_spreadsheet('NODATE:reco_punch_sheet'); --Added by RS on 03/04/2026.
    reco_web_functions.col_span := 10;
    reco_web_functions.add_header_column(
      'Internal Error 2050 - History and Processing is Corrupted. Contact MIS.');
    reco_web_functions.print_header;
    reco_web_Functions.close_spreadsheet;
    RETURN;
  END IF;
  
  rstx_punchplanning_rpt(TO_CHAR(vn_TmpHistId));
END;

--------------------------------------------------------------------------------
-- rstx_punchplanning_rpt
PROCEDURE rstx_punchplanning_rpt (pi_GivenHistId IN varchar2)
IS
  
  vr_Params reco_rstx_userparam_hist%ROWTYPE;
  
  vn_QtyColumnsInSpreadsheet number;
  
  vn_GivenHistId number;
  
  vd_FirstDate date;
  
  vd_CurrentDate date;
  
BEGIN -- rstx_punchplanning_rpt

  ---
  -- Access user parameters
  ---
  
  vn_GivenHistId := TO_NUMBER(pi_GivenHistId);
  
  BEGIN
    SELECT * INTO vr_Params
    FROM reco_rstx_userparam_hist WHERE cutsch_hist_id = vn_GivenHistId;
    
    IF vr_Params.first_date_of_reqs IS NULL
    OR vr_Params.first_date_of_cutting IS NULL
    OR vr_Params.first_date_of_cutting < vr_Params.first_date_of_reqs
    THEN RAISE NO_DATA_FOUND;
    END IF;
  EXCEPTION
    WHEN others
    THEN 
      reco_web_functions.reset_sheet;
      reco_web_functions.table_attr := 'border="1" frame="border" rules="all"';
--      reco_web_functions.open_spreadsheet; 
      reco_web_functions.open_spreadsheet('NODATE:reco_punch_sheet'); --Added by RS on 03/04/2026.
      reco_web_functions.col_span := 10;
      reco_web_functions.add_header_column(
      'Internal Error 2033 - User params inaccessible. Contact MIS');
      reco_web_functions.print_header;
      reco_web_Functions.close_spreadsheet;
      RETURN;
  END;
  
  vn_QtyColumnsInSpreadsheet := 7;
  
  DECLARE
    vc_TmpOutMsg varchar2(1000);
  BEGIN
    
    vc_TmpOutMsg := check_rpt_daterange_valid(1);
    
    IF vc_TmpOutMsg != 'DONE'
    THEN
      reco_web_functions.reset_sheet;
      reco_web_functions.table_attr := 'border="1" frame="border" rules="all"';
--      reco_web_functions.open_spreadsheet;
      reco_web_functions.open_spreadsheet('NODATE:reco_punch_sheet'); --Added by RS on 03/04/2026.
      reco_web_functions.col_span := 10;
      reco_web_functions.add_header_column(
        'Internal Error 2068 - Invalid History / Date Tieback. Contact MIS.');
      reco_web_functions.print_header;
      reco_web_Functions.close_spreadsheet;
      RETURN;
    END IF;
    
    vc_TmpOutMsg := get_date_toshowin_rpt(vn_GivenHistId,
      FALSE,1,
      vr_Params.first_date_of_reqs,vr_Params.first_date_of_cutting,
      vd_FirstDate);
    
    IF vc_TmpOutMsg != 'DONE'
    THEN
      reco_web_functions.reset_sheet;
      reco_web_functions.table_attr := 'border="1" frame="border" rules="all"';
--      reco_web_functions.open_spreadsheet; 
      reco_web_functions.open_spreadsheet('NODATE:reco_punch_sheet'); --Added by RS on 03/04/2026.
      reco_web_functions.col_span := 10;
      reco_web_functions.add_header_column(
        'Internal Error 2060 - Invalid History / Date Tieback. Contact MIS.');
      reco_web_functions.print_header;
      reco_web_Functions.close_spreadsheet;
      RETURN;
    END IF;
  END;
  
  ---
  -- Prepare spreadsheet
  ---
  
  reco_web_functions.reset_sheet;
  reco_web_functions.table_attr := 'border="1" frame="border" rules="all"';
--  reco_web_functions.open_spreadsheet;
  reco_web_functions.open_spreadsheet('NODATE:reco_punch_sheet'); --Added by RS on 03/04/2026.
  
  ---
  -- Print history info if needed
  ---
  
  DECLARE
    vn_MaxHist number;
    vc_TmpHistText reco_rstx_cutsch_hist.runname%TYPE;
  BEGIN
    SELECT MAX(cutsch_hist_id) INTO vn_MaxHist FROM reco_rstx_cutsch_hist;
    
    IF vn_GivenHistId != vn_MaxHist
    THEN
      SELECT runname INTO vc_TmpHistText
      FROM reco_rstx_cutsch_hist WHERE cutsch_hist_id = vn_GivenHistId;
  
      reco_web_functions.clear_headers;
  
      reco_web_functions.col_span := vn_QtyColumnsInSpreadsheet;
      reco_web_functions.add_header_column(
        'Punch Schedule History - '||vc_TmpHistText);
      reco_web_functions.print_header;
    END IF;
  END;
  
  ---
  -- Print Report header
  ---
  
  reco_web_functions.clear_headers;
  
  reco_web_functions.cell_attr := '';
  reco_web_functions.col_span := vn_QtyColumnsInSpreadsheet;
  reco_web_functions.add_header_column('Punch Report');
  reco_web_functions.print_header;
  
  reco_web_functions.clear_headers;
  reco_web_functions.cell_attr := '';
  reco_web_functions.col_span  := vn_QtyColumnsInSpreadsheet;
  reco_web_functions.add_header_column(' ');
  reco_web_functions.print_header;
  
  reco_web_functions.clear_headers;
  reco_web_functions.cell_attr := '';
  reco_web_functions.col_span  := vn_QtyColumnsInSpreadsheet;
  reco_web_functions.add_header_column(' ');
  reco_web_functions.print_header;
  
  ---
  -- Print data headers and data lines in a loop
  ---
  
  DECLARE
    -- CONTINUE HERE
    -- 
    -- NOTE #1
    -- CONTINUE HERE DOES NOT INCLUDE CUTSCH PUNCHES AS INV
    -- 
    -- NOTE #2
    -- This does not round galv/black mixed to the nearest 100
    -- this is because the cutschedule is not budgeting B/G requirements
    -- separately.
    -- If you want to round Black/Galv mix, then you need to adjust the
    -- Cut Schedule so that Black/Galv require separate runs etc...
    -- CONTINUE HERE
    CURSOR cur_PunchInfo
    IS
      SELECT  caldayhist.thedate rundate,
              punrunhist.run_number run_number,
              NVL(subQNPInv_Galv.quantity,
                    NVL(subQNPInv_Black.quantity,0)) reqinv,
              NVL(subQFirstReqDate_Galv.reqlength,
                    subQFirstReqDate_Black.reqlength) reqlength,
              NVL(subQFirstReqDate_Galv.reqtype,
                    subQFirstReqDate_Black.reqtype) reqtype,
              NVL(subQFirstReqDate_Galv.reqpunch,
                    subQFirstReqDate_Black.reqpunch) reqpunch,
              'G' galvreqcoating,
              subQFirstReqDate_Galv.thedate galvfirstshipdate,
              subQFirstReqDate_Galv.reqpunch||
              subQFirstReqDate_Galv.reqtype||
              'G'||subQNPInv_Galv.charlength galvreqpart,
              subQTotAsg_Galv.totalpcs galvtotalpcs,
              'B' blackreqcoating,
              subQFirstReqDate_Black.thedate blackfirstshipdate,
              subQFirstReqDate_Black.reqpunch||
              subQFirstReqDate_Black.reqtype||
              'B'||subQNPInv_Black.charlength blackreqpart,
              subQTotAsg_Black.totalpcs blacktotalpcs,
              NVL(punovghist.overage_qty,0) overage_qty,
              NVL(subQFirstReqDate_Galv.thedate,
                    subQFirstReqDate_Black.thedate) sortord_date
      FROM  reco_rstx_calday_hist caldayhist,
            reco_rstx_punrun_hist punrunhist,
            reco_rstx_punovg_hist punovghist,
            (
              SELECT  punrun.punrun_id,
                      punreq.reqpunch,
                      punreq.reqlength,
                      punreq.reqtype,
                      MIN(punreq.reqdate) thedate
              FROM  reco_rstx_punrun_hist punrun,
                    reco_rstx_punasg_hist punasg,
                    reco_rstx_punreq_hist punreq
              WHERE   punrun.punrun_id = punasg.punrun_id
              AND     punasg.punreq_id = punreq.punreq_id
              AND     punasg.qty_asg_black > 0
              AND     punrun.cutsch_hist_id = vn_GivenHistId
              AND     punasg.cutsch_hist_id = vn_GivenHistId
              AND     punreq.cutsch_hist_id = vn_GivenHistId
              GROUP BY  punrun.punrun_id,
                        punreq.reqpunch,
                        punreq.reqlength,
                        punreq.reqtype
            ) subQFirstReqDate_Black,
            (
              SELECT  subasg.punrun_id,
                      SUM(subasg.qty_asg_black) totalpcs
              FROM  reco_rstx_punasg_hist subasg
              WHERE   subasg.cutsch_hist_id = vn_GivenHistId
              AND     subasg.qty_asg_black > 0
              GROUP BY  subasg.punrun_id
            ) subQTotAsg_Black,
            reco_rstx_originvqty_hist subQNPInv_Black,
            (
              SELECT  punrun.punrun_id,
                      punreq.reqpunch,
                      punreq.reqlength,
                      punreq.reqtype,
                      MIN(punreq.reqdate) thedate
              FROM  reco_rstx_punrun_hist punrun,
                    reco_rstx_punasg_hist punasg,
                    reco_rstx_punreq_hist punreq
              WHERE   punrun.punrun_id = punasg.punrun_id
              AND     punasg.punreq_id = punreq.punreq_id
              AND     punasg.qty_asg_galv > 0
              AND     punrun.cutsch_hist_id = vn_GivenHistId
              AND     punasg.cutsch_hist_id = vn_GivenHistId
              AND     punreq.cutsch_hist_id = vn_GivenHistId
              GROUP BY  punrun.punrun_id,
                        punreq.reqpunch,
                        punreq.reqlength,
                        punreq.reqtype
            ) subQFirstReqDate_Galv,
            (
              SELECT  subasg.punrun_id,
                      SUM(subasg.qty_asg_galv) totalpcs
              FROM  reco_rstx_punasg_hist subasg
              WHERE   subasg.cutsch_hist_id = vn_GivenHistId
              AND     subasg.qty_asg_galv > 0
              GROUP BY  subasg.punrun_id
            ) subQTotAsg_Galv,
            reco_rstx_originvqty_hist subQNPInv_Galv
      WHERE   caldayhist.calday_id = punrunhist.calday_id
      AND     punrunhist.punrun_id = punovghist.punrun_id (+)
      AND     punrunhist.punrun_id = subQFirstReqDate_Black.punrun_id (+)
      AND     punrunhist.punrun_id = subQTotAsg_Black.punrun_id (+)
      AND     subQFirstReqDate_Black.reqtype = subQNPInv_Black.thetype (+)
      AND     subQFirstReqDate_Black.reqlength = subQNPInv_Black.numlength (+)
      AND     subQNPInv_Black.thecoat (+) = 'B'
      AND     subQNPInv_Black.thepunch (+) = 'N'
      AND     punrunhist.punrun_id = subQFirstReqDate_Galv.punrun_id (+)
      AND     punrunhist.punrun_id = subQTotAsg_Galv.punrun_id (+)
      AND     subQFirstReqDate_Galv.reqtype = subQNPInv_Galv.thetype (+)
      AND     subQFirstReqDate_Galv.reqlength = subQNPInv_Galv.numlength (+)
      AND     subQNPInv_Galv.thecoat (+) = 'B'
      AND     subQNPInv_Galv.thepunch (+) = 'N'
      AND     caldayhist.cutsch_hist_id = vn_GivenHistId
      AND     punrunhist.cutsch_hist_id = vn_GivenHistId
      AND     punovghist.cutsch_hist_id (+) = vn_GivenHistId
      AND     subQNPInv_Black.cutsch_hist_id (+) = vn_GivenHistId
      AND     subQNPInv_Galv.cutsch_hist_id (+) = vn_GivenHistId
      ORDER BY  caldayhist.thedate,
                punrunhist.run_number;
    
    vb_HadPreviousRec BOOLEAN;
    rec_PrevPunchInfo cur_PunchInfo%ROWTYPE;
  BEGIN
    
    vb_HadPreviousRec := FALSE;
    
    FOR currRec IN cur_PunchInfo
    LOOP
      IF vb_HadPreviousRec = FALSE
      OR currRec.rundate != rec_PrevPunchInfo.rundate
      THEN
        reco_web_functions.clear_headers;
        reco_web_functions.col_span  := vn_QtyColumnsInSpreadsheet;
        reco_web_functions.cell_attr := '';
        --reco_web_functions.col_span  := '';
        --reco_web_functions.col_span := 1;
        --reco_web_functions.col_span := 4;
        --reco_web_functions.cell_attr := 'bgcolor = #FF0000';
        --reco_web_functions.cell_attr :=  ' <font color=RED';
        --reco_web_functions.cell_attr := 'bgcolor =#FFFFFF <font color=RED';
        reco_web_functions.add_header_column(
          'Date '||TO_CHAR(currRec.rundate, 'DD-MON-YYYY'));
        reco_web_functions.print_header;
        
        reco_web_functions.clear_headers;
        reco_web_functions.col_span  := 1;
        reco_web_functions.cell_attr := '';
        reco_web_functions.add_header_column('AM INV<br>NoPn');
        reco_web_functions.col_span  := 1;
        reco_web_functions.cell_attr := '';
        reco_web_functions.add_header_column('Strip<br>Length');
        reco_web_functions.col_span  := 1;
        reco_web_functions.cell_attr := '';
        reco_web_functions.add_header_column('Part<br>Type');
        reco_web_functions.col_span  := 1;
        reco_web_functions.cell_attr := '';
        reco_web_functions.add_header_column('Punch');
        reco_web_functions.col_span  := 1;
        reco_web_functions.cell_attr := '';
        reco_web_functions.add_header_column('Qty to<br>Punch');
        reco_web_functions.col_span  := 1;
        reco_web_functions.cell_attr := '';
        reco_web_functions.add_header_column('Part');
        reco_web_functions.col_span  := 1;
        reco_web_functions.cell_attr := '';
        reco_web_functions.add_header_column('1st Shipment');
        reco_web_functions.col_span  := 1;
        reco_web_functions.cell_attr := '';
        reco_web_functions.print_header;
      END IF;
      
      IF NVL(currRec.galvtotalpcs,0) != 0
      THEN
        reco_web_functions.col_span := 1;
        reco_web_functions.cell_attr := '';
        
        reco_web_functions.add_data_column(
          TO_CHAR(currRec.reqinv));
        reco_web_functions.add_data_column(
          TO_CHAR(currRec.reqlength));
        reco_web_functions.add_data_column(
          currRec.reqtype);
        reco_web_functions.add_data_column(
          currRec.reqpunch||'P');
        reco_web_functions.add_data_column( -- Default assume overage is galv
          TO_CHAR(currRec.galvtotalpcs+currRec.overage_qty));
        reco_web_functions.add_data_column(
          currRec.galvreqpart);
        reco_web_functions.add_data_column(
          TO_CHAR(currRec.galvfirstshipdate,'DD-MON'));
        
        reco_web_functions.print_datarow;
      END IF;
      
      IF NVL(currRec.blacktotalpcs,0) != 0
      THEN
        reco_web_functions.col_span := 1;
        reco_web_functions.cell_attr := 'bgcolor =#606060 <font color=WHITE';
        
        reco_web_functions.add_data_column(
          TO_CHAR(currRec.reqinv));
        reco_web_functions.add_data_column(
          TO_CHAR(currRec.reqlength));
        reco_web_functions.add_data_column(
          currRec.reqtype);
        reco_web_functions.add_data_column(
          currRec.reqpunch||'P');
        IF NVL(currRec.galvtotalpcs,0) != 0
        THEN
          reco_web_functions.add_data_column(
            TO_CHAR(currRec.blacktotalpcs));
        ELSIF NVL(currRec.galvtotalpcs,0) = 0
        THEN
          reco_web_functions.add_data_column(
            TO_CHAR(currRec.blacktotalpcs+currRec.overage_qty));
        END IF;
        reco_web_functions.add_data_column(
          currRec.blackreqpart);
        reco_web_functions.add_data_column(
          TO_CHAR(currRec.blackfirstshipdate,'DD-MON'));
        
        reco_web_functions.print_datarow;
      END IF;
      
      rec_PrevPunchInfo := currRec;
      vb_HadPreviousRec := TRUE;
    END LOOP;
  END;
  
  ---
  -- Close spreadsheet
  ---
  
  reco_web_Functions.close_spreadsheet;
  
EXCEPTION
 WHEN others
 THEN
   htp.tableclose;
   htp.print('Report Exception Condition:'||sqlerrm|| -- CONTINUE HERE ADD TO OTHER FUNCTS
            ' Date:'||TO_CHAR(SYSDATE,'DD-MON-YYYY'));
   htp.htmlClose;
END; -- rstx_punchplanning_rpt

--------------------------------------------------------------------------------
-- rstx_galv_rpt
PROCEDURE rstx_galv_rpt
IS
  vn_TmpHistId number;
BEGIN
  SELECT MAX(cutsch_hist_id) INTO vn_TmpHistId FROM reco_rstx_cutsch_hist;
  
  IF vn_TmpHistId IS NULL
  THEN
    reco_web_functions.reset_sheet;
    reco_web_functions.table_attr := 'border="1" frame="border" rules="all"';
--    reco_web_functions.open_spreadsheet;
    reco_web_functions.open_spreadsheet('NODATE:reco_galvanize_report'); --Added by RS on 03/04/2026.
    reco_web_functions.col_span := 10;
    reco_web_functions.add_header_column(
      'Internal Error 2051 - History and Processing is Corrupted. Contact MIS.');
    reco_web_functions.print_header;
    reco_web_Functions.close_spreadsheet;
    RETURN;
  END IF;
  
  rstx_galv_rpt(TO_CHAR(vn_TmpHistId));
END;

--------------------------------------------------------------------------------
-- rstx_galv_rpt
PROCEDURE rstx_galv_rpt (pi_GivenHistId IN varchar2)
IS
  CURSOR cur_galvinfo(pi_GivenMinLen IN number,
                      pi_GivenMaxLen IN number,
                      pi_GivenFirstDate IN date,
                      pi_GivenLastDate IN date,
                      pi_CurHistoryId IN number)
  IS
    -- Query Inventory Qtys - S504G-ValidLength
    SELECT  1 sortord_S54orOther,
            roiqGalv.segment1,
            roiqGalv.thepunch,
            roiqGalv.thetype,
            roiqGalv.thecoat,
            roiqGalv.numlength,
            roiqGalv.charlength,
            NULL reqdate,
            NVL(roiqBlack.quantity,0) origInvQtyBlack,
            roiqGalv.quantity origInvQtyGalv,
            NULL reqQtyGalv
    FROM  reco_rstx_originvqty_hist roiqGalv,
          reco_rstx_originvqty_hist roiqBlack
    WHERE   roiqGalv.thepunch = 'S'
    AND     roiqGalv.thetype IN ( '504','506')
    AND     roiqGalv.numlength >= pi_GivenMinLen
    AND     roiqGalv.numlength <= pi_GivenMaxLen
    AND     roiqGalv.thecoat = 'G'
    AND     roiqGalv.inventory_item_id IS NOT NULL
    AND     roiqGalv.cutsch_hist_id = pi_CurHistoryId
    AND     roiqGalv.actual_attribute4 = roiqBlack.segment1 (+)
    AND     roiqBlack.cutsch_hist_id (+) = pi_CurHistoryId
    UNION
    -- Query Inventory Qtys - all-other parts
    SELECT  2 sortord_S54orOther,
            roiqGalv.segment1,
            roiqGalv.thepunch,
            roiqGalv.thetype,
            roiqGalv.thecoat,
            roiqGalv.numlength,
            roiqGalv.charlength,
            NULL reqdate,
            NVL(roiqBlack.quantity,0) origInvQtyBlack,
            roiqGalv.quantity origInvQtyGalv,
            NULL reqQtyGalv
    FROM  reco_rstx_originvqty_hist roiqGalv,
          reco_rstx_originvqty_hist roiqBlack
    WHERE   (roiqGalv.thepunch != 'S'
                  OR roiqGalv.thetype NOT IN ( '504','506')
                  OR roiqGalv.numlength < pi_GivenMinLen
                  OR roiqGalv.numlength > pi_GivenMaxLen)
    AND     roiqGalv.thecoat = 'G'
    AND     roiqGalv.inventory_item_id IS NOT NULL
    AND     roiqGalv.cutsch_hist_id = pi_CurHistoryId
    AND     roiqGalv.actual_attribute4 = roiqBlack.segment1 (+)
    AND     roiqBlack.cutsch_hist_id (+) = pi_CurHistoryId
    AND     EXISTS  (
                      SELECT  'Y'
                      FROM  reco_rstx_galvreq_hist subgalvreq
                      WHERE   roiqGalv.numlength = subgalvreq.reqlength
                      AND     roiqGalv.thetype = subgalvreq.reqtype
                      AND     (
                                (roiqGalv.thepunch = 'S'
                                        AND subGalvReq.req_sp_g > 0)
                                OR
                                (roiqGalv.thepunch = 'D'
                                        AND subGalvReq.req_dp_g > 0)
                              )
                      AND     subgalvreq.reqdate >= pi_GivenFirstDate
                      AND     subgalvreq.reqdate <= pi_GivenLastDate
                      AND     subgalvreq.cutsch_hist_id = pi_CurHistoryId
                    )
    UNION
    -- Query Requirements: S504G-ValidLength parts that have date/reqs
    SELECT  1 sortord_S54orOther,
            roiqGalv.segment1,
            roiqGalv.thepunch,
            roiqGalv.thetype,
            roiqGalv.thecoat,
            roiqGalv.numlength,
            roiqGalv.charlength,
            galvreq.reqdate reqdate,
            NULL origInvQtyBlack,
            NULL origInvQtyGalv,
            CASE
              WHEN roiqGalv.thepunch = 'S'
              THEN galvreq.req_sp_g
              WHEN roiqGalv.thepunch = 'D'
              THEN galvreq.req_dp_g
              ELSE -1
            END reqQtyGalv
    FROM  reco_rstx_originvqty_hist roiqGalv,
          reco_rstx_galvreq_hist galvreq
    WHERE   roiqGalv.thepunch = 'S'
    AND     roiqGalv.thetype IN( '504','506' )
    AND     roiqGalv.numlength >= pi_GivenMinLen
    AND     roiqGalv.numlength <= pi_GivenMaxLen
    AND     roiqGalv.thecoat = 'G'
    AND     roiqGalv.inventory_item_id IS NOT NULL
    AND     roiqGalv.numlength = galvreq.reqlength
    AND     roiqGalv.thetype = galvreq.reqtype
    AND     (
              (roiqGalv.thepunch = 'S'
                      AND galvreq.req_sp_g > 0)
              OR
              (roiqGalv.thepunch = 'D'
                      AND galvreq.req_dp_g > 0)
            )
    AND     galvreq.reqdate >= pi_GivenFirstDate
    AND     galvreq.reqdate <= pi_GivenLastDate
    AND     roiqGalv.cutsch_hist_id = pi_CurHistoryId
    AND     galvreq.cutsch_hist_id = pi_CurHistoryId
    UNION
    -- Query Requirements: all-other parts that have date/reqs
    SELECT  2 sortord_S54orOther,
            roiqGalv.segment1,
            roiqGalv.thepunch,
            roiqGalv.thetype,
            roiqGalv.thecoat,
            roiqGalv.numlength,
            roiqGalv.charlength,
            galvreq.reqdate reqdate,
            NULL origInvQtyBlack,
            NULL origInvQtyGalv,
            CASE
              WHEN roiqGalv.thepunch = 'S'
              THEN galvreq.req_sp_g
              WHEN roiqGalv.thepunch = 'D'
              THEN galvreq.req_dp_g
              ELSE -1
            END reqQtyGalv
    FROM  reco_rstx_originvqty_hist roiqGalv,
          reco_rstx_galvreq_hist galvreq
    WHERE   (roiqGalv.thepunch != 'S'
                  OR roiqGalv.thetype NOT IN ( '504','506')
                  OR roiqGalv.numlength < pi_GivenMinLen
                  OR roiqGalv.numlength > pi_GivenMaxLen)
    AND     roiqGalv.thecoat = 'G'
    AND     roiqGalv.inventory_item_id IS NOT NULL
    AND     roiqGalv.numlength = galvreq.reqlength
    AND     roiqGalv.thetype = galvreq.reqtype
    AND     (
              (roiqGalv.thepunch = 'S'
                      AND galvreq.req_sp_g > 0)
              OR
              (roiqGalv.thepunch = 'D'
                      AND galvreq.req_dp_g > 0)
            )
    AND     galvreq.reqdate >= pi_GivenFirstDate
    AND     galvreq.reqdate <= pi_GivenLastDate
    AND     roiqGalv.cutsch_hist_id = pi_CurHistoryId
    AND     galvreq.cutsch_hist_id = pi_CurHistoryId
    ORDER BY  sortord_S54orOther,
              segment1,
              reqdate NULLS FIRST;
  
  TYPE coll_galvinfo IS TABLE OF cur_galvinfo%ROWTYPE;
  oTheGalvInfo coll_galvinfo; -- Fetched, so don't initialize
  --oTheGalvInfo coll_galvinfo := coll_galvinfo(); -- Initialize since not fetched
  nCtrGalvInfo number;
  
  vn_GivenHistId number;
  
  vr_Params reco_rstx_userparam_hist%ROWTYPE;
  
  vn_QtyDaysShown number;
  vd_FirstDateShown date;
  vd_LastDateShown date;
  
BEGIN -- rstx_galv_rpt
  
  ---
  -- Access user parameters
  ---
  
  vn_GivenHistId := TO_NUMBER(pi_GivenHistId);
  
  BEGIN
    SELECT * INTO vr_Params
    FROM reco_rstx_userparam_hist WHERE cutsch_hist_id = vn_GivenHistId;
    
    IF vr_Params.min_cut_allowed IS NULL
    OR vr_Params.max_cut_allowed IS NULL
    OR vr_Params.first_date_of_reqs IS NULL
    OR vr_Params.first_date_of_cutting IS NULL
    OR vr_Params.first_date_of_cutting < vr_Params.first_date_of_reqs
    THEN RAISE NO_DATA_FOUND;
    END IF;
  EXCEPTION
    WHEN others
    THEN 
      reco_web_functions.reset_sheet;
      reco_web_functions.table_attr := 'border="1" frame="border" rules="all"';
--      reco_web_functions.open_spreadsheet;
      reco_web_functions.open_spreadsheet('NODATE:reco_galvanize_report'); --Added by RS on 03/04/2026.
      reco_web_functions.col_span := 10;
      reco_web_functions.add_header_column(
      'Internal Error 2027 - User params inaccessible. Contact MIS');
      reco_web_functions.print_header;
      reco_web_Functions.close_spreadsheet;
      RETURN;
  END;
  
  ---
  -- Determine values for:
  -- vn_QtyDaysShown / vd_FirstDateShown / vd_LastDateShown
  ---
  
  -- NOTE: Since the Galvanizing "Schedule" does not link
  --       to reco_rstx_calday_hist, then you cannot implement any
  --       "business days" logic here.
  -- 
  -- The galvanizing schedule does not use the reco_rstx_...Asg table
  -- like the other schedules do. Instead, it directly prints dates
  -- and requirements using reco_rstx_galvreq_hist table.
  -- 
  -- But galvreq is based on Shipments, right?
  -- Correct.
  -- But we don't save shipment history.
  -- 
  -- This all means that we have special "date logic" for the galv schedule
  
  -- Do NOT use the check_rpt_daterange_valid method
  --   >> Because this report is based off requirements, not calday assignments
  -- Do NOT use the get_date_toshowin_rpt method
  --   >> Because this report is based off requirements, not calday assignments
  -- Do NOT use the shipping tables
  --   >> Because this report doesn't show shipping
  
  vn_QtyDaysShown := 10;
  
  DECLARE
    vd_TmpGalvReqDate date;
  BEGIN
    SELECT MIN(reqdate) INTO vd_TmpGalvReqDate
    FROM reco_rstx_galvreq_hist WHERE cutsch_hist_id = vn_GivenHistId;
    
    vd_FirstDateShown := vr_Params.first_date_of_cutting;
    IF vd_TmpGalvReqDate IS NOT NULL
    AND vd_FirstDateShown > vd_TmpGalvReqDate
    THEN vd_FirstDateShown := vd_TmpGalvReqDate;
    END IF; -- This is okay. Remember: we're not using reco_rstx_calday_hist
  END;
  
  -- Based on the description above, we cannot iterate via CALDAY table
  -- or by ShipmentDates, so we use good old fashioned sysdate iteration
  vd_LastDateShown := vd_FirstDateShown + (vn_QtyDaysShown - 1);
  
  ---
  -- Get all possible data for this report
  ---
  
  OPEN cur_galvinfo(vr_Params.min_cut_allowed,vr_Params.max_cut_allowed,
                    vd_FirstDateShown,vd_LastDateShown,
                    vn_GivenHistId);
  FETCH cur_galvinfo BULK COLLECT INTO oTheGalvInfo;
  CLOSE cur_galvinfo;
  
  ---
  -- Prepare spreadsheet
  ---
  
  reco_web_functions.reset_sheet;
  reco_web_functions.table_attr := 'border="1" frame="border" rules="all"';
--  reco_web_functions.open_spreadsheet;
  reco_web_functions.open_spreadsheet('NODATE:reco_galvanize_report'); --Added by RS on 03/04/2026.
  
  ---
  -- Print history info if needed
  ---
  
  DECLARE
    vn_MaxHist number;
    vc_TmpHistText reco_rstx_cutsch_hist.runname%TYPE;
  BEGIN
    SELECT MAX(cutsch_hist_id) INTO vn_MaxHist FROM reco_rstx_cutsch_hist;
    
    IF vn_GivenHistId != vn_MaxHist
    THEN
      SELECT runname INTO vc_TmpHistText
      FROM reco_rstx_cutsch_hist WHERE cutsch_hist_id = vn_GivenHistId;
  
      reco_web_functions.clear_headers;
  
      reco_web_functions.col_span := 3 + vn_QtyDaysShown + 8;
      reco_web_functions.add_header_column(
        'Galv Schedule History - '||vc_TmpHistText);
      reco_web_functions.print_header;
    END IF;
  END;
  
  ---
  -- Print First Header Row
  ---
  
  reco_web_functions.clear_headers;
  
  reco_web_functions.col_span := 3;
  reco_web_functions.cell_attr := '';
  reco_web_functions.add_header_column('Galvanizing<br>Report');
  
  IF vn_QtyDaysShown >= 4
  THEN
    reco_web_functions.col_span := 4;
    reco_web_functions.cell_attr := '';
    reco_web_functions.add_header_column('Run Date:<br>'||TO_CHAR(SYSDATE,'DD-MON-YYYY'));
  END IF;
  
  IF vn_QtyDaysShown >= 8
  THEN
    DECLARE
      vd_DateOfRun date;
    BEGIN
      BEGIN
        SELECT thetime INTO vd_DateOfRun
        FROM reco_rstx_cutsch_hist WHERE cutsch_hist_id = vn_GivenHistId;
      EXCEPTION
        WHEN others THEN vd_DateOfRun := NULL;
      END;
      
      vd_DateOfRun := NVL(vd_DateOfRun, TO_DATE('01-JAN-2000','DD-MON-YYYY'));
      
      reco_web_functions.col_span := 4;
      reco_web_functions.cell_attr := '';
      reco_web_functions.add_header_column(
        'Cut Schedule Run Date:<br>'||TO_CHAR(vd_DateOfRun,'DD-MON-YYYY'));
    END;
  END IF;
  
  DECLARE
    vn_NewColSpan number;
  BEGIN
    vn_NewColSpan := 0;
    
    IF vn_QtyDaysShown >= 8
    THEN vn_NewColSpan := vn_QtyDaysShown - 8;
    END IF;
    
    IF vn_NewColSpan > 0
    THEN
      reco_web_functions.col_span := vn_NewColSpan;
      reco_web_functions.cell_attr := '';
      reco_web_functions.add_header_column(' ');
    END IF;
  END;
  
  reco_web_functions.col_span := 2;
  reco_web_functions.cell_attr := '';
  reco_web_functions.add_header_column('NIGHT');
  
  reco_web_functions.col_span := 2;
  reco_web_functions.cell_attr := '';
  reco_web_functions.add_header_column('DAY');
  
  reco_web_functions.col_span := 1;
  reco_web_functions.cell_attr := '';
  reco_web_functions.add_header_column('GALV');
  
  reco_web_functions.col_span := 2;
  reco_web_functions.cell_attr := '';
  reco_web_functions.add_header_column('REWORKS');
  
  reco_web_functions.col_span := 1;
  reco_web_functions.cell_attr := '';
  reco_web_functions.add_header_column(' ');
  
  reco_web_functions.print_header;
  
  ---
  -- Print Second Header Row
  ---
  
  reco_web_functions.clear_headers;
  
  reco_web_functions.col_span := 1;
  reco_web_functions.cell_attr := '';
  reco_web_functions.add_header_column('Part');
  
  reco_web_functions.col_span := 1;
  reco_web_functions.cell_attr := '';
  reco_web_functions.add_header_column('Blk<br>Inv');
  
  reco_web_functions.col_span := 1;
  reco_web_functions.cell_attr := '';
  reco_web_functions.add_header_column('Galv<br>Inv');
  
  DECLARE
    vd_CurrDate date;
  BEGIN
    vd_CurrDate := vd_FirstDateShown;
    
    LOOP
      IF vd_CurrDate > vd_LastDateShown
      THEN exit;
      END IF;
      
      reco_web_functions.col_span := 1;
      reco_web_functions.cell_attr := '';
      reco_web_functions.add_header_column(
        TO_CHAR(vd_CurrDate,'MM/DD')||'<br>'||TO_CHAR(vd_CurrDate,'DY'));
      
      vd_CurrDate := vd_CurrDate + 1;
    END LOOP;
  END;
  
  reco_web_functions.col_span := 1;
  reco_web_functions.cell_attr := '';
  reco_web_functions.add_header_column('IN');
  
  reco_web_functions.col_span := 1;
  reco_web_functions.cell_attr := '';
  reco_web_functions.add_header_column('OUT');
  
  reco_web_functions.col_span := 1;
  reco_web_functions.cell_attr := '';
  reco_web_functions.add_header_column('IN');
  
  reco_web_functions.col_span := 1;
  reco_web_functions.cell_attr := '';
  reco_web_functions.add_header_column('OUT');
  
  reco_web_functions.col_span := 1;
  reco_web_functions.cell_attr := '';
  reco_web_functions.add_header_column('Total');
  
  reco_web_functions.col_span := 1;
  reco_web_functions.cell_attr := '';
  reco_web_functions.add_header_column('IN');
  
  reco_web_functions.col_span := 1;
  reco_web_functions.cell_attr := '';
  reco_web_functions.add_header_column('OUT');
  
  reco_web_functions.col_span := 1;
  reco_web_functions.cell_attr := '';
  reco_web_functions.add_header_column('Part');
  
  reco_web_functions.print_header;
  
  ---
  -- Print Rows
  ---
  
  IF oTheGalvInfo.count = 0
  THEN reco_web_Functions.close_spreadsheet; RETURN;
  END IF;
  
  nCtrGalvInfo := 1;
  
  DECLARE
    vd_CurrentDate date;
  BEGIN
    
    LOOP
      IF nCtrGalvInfo > oTheGalvInfo.count
      OR oTheGalvInfo(nCtrGalvInfo).reqdate IS NOT NULL
      THEN
        reco_web_functions.col_span := 1;
        reco_web_functions.cell_attr := '';
        reco_web_functions.add_header_column(
          'Internal Error 2047 - PrintRow loop is incorrectly resetting. Contact MIS');
        reco_web_functions.print_datarow;
        reco_web_functions.close_spreadsheet;
        RETURN;
      END IF;
      
      reco_web_functions.col_span := 1;
      reco_web_functions.cell_attr := '';
      reco_web_functions.add_data_column(
        oTheGalvInfo(nCtrGalvInfo).segment1);
      
      reco_web_functions.col_span := 1;
      reco_web_functions.cell_attr := '';
      reco_web_functions.add_data_column(
        oTheGalvInfo(nCtrGalvInfo).origInvQtyBlack);
      
      reco_web_functions.col_span := 1;
      reco_web_functions.cell_attr := '';
      reco_web_functions.add_data_column(
        oTheGalvInfo(nCtrGalvInfo).origInvQtyGalv);
      
      nCtrGalvInfo := nCtrGalvInfo + 1;
      
      vd_CurrentDate := vd_FirstDateShown;
      
      LOOP
        IF nCtrGalvInfo <= oTheGalvInfo.count
        AND oTheGalvInfo(nCtrGalvInfo).reqdate IS NOT NULL
        AND oTheGalvInfo(nCtrGalvInfo).reqdate = vd_CurrentDate
        THEN
          reco_web_functions.col_span := 1;
          reco_web_functions.cell_attr := '';
          reco_web_functions.add_data_column(
            TO_CHAR(oTheGalvInfo(nCtrGalvInfo).reqQtyGalv));
          
          nCtrGalvInfo := nCtrGalvInfo + 1;
        ELSE
          reco_web_functions.col_span := 1;
          reco_web_functions.cell_attr := '';
          reco_web_functions.add_data_column(' ');
        END IF;
        
        IF vd_CurrentDate = vd_LastDateShown
        THEN exit;
        END IF;
        
        vd_CurrentDate := vd_CurrentDate + 1;
      END LOOP;
      
      reco_web_functions.col_span := 1;
      reco_web_functions.cell_attr := '';
      reco_web_functions.add_data_column(' ');
      
      reco_web_functions.col_span := 1;
      reco_web_functions.cell_attr := '';
      reco_web_functions.add_data_column(' ');
      
      reco_web_functions.col_span := 1;
      reco_web_functions.cell_attr := '';
      reco_web_functions.add_data_column(' ');
      
      reco_web_functions.col_span := 1;
      reco_web_functions.cell_attr := '';
      reco_web_functions.add_data_column(' ');
      
      reco_web_functions.col_span := 1;
      reco_web_functions.cell_attr := '';
      reco_web_functions.add_data_column(' ');
      
      reco_web_functions.col_span := 1;
      reco_web_functions.cell_attr := '';
      reco_web_functions.add_data_column(' ');
      
      reco_web_functions.col_span := 1;
      reco_web_functions.cell_attr := '';
      reco_web_functions.add_data_column(' ');
      
      reco_web_functions.col_span := 1;
      reco_web_functions.cell_attr := '';
      reco_web_functions.add_data_column(
        oTheGalvInfo(nCtrGalvInfo-1).segment1);
      
      reco_web_functions.print_datarow;
      
      IF nCtrGalvInfo = (oTheGalvInfo.count) + 1
      THEN exit;
      ELSIF nCtrGalvInfo > (oTheGalvInfo.count) + 1
      THEN
        reco_web_functions.col_span := 1;
        reco_web_functions.cell_attr := '';
        reco_web_functions.add_header_column(
          'Internal Error 2048 - Loop Counter is going overload. Contact MIS');
        reco_web_functions.print_datarow;
        reco_web_functions.close_spreadsheet;
        RETURN;
      END IF;
      
    END LOOP;
    
  END;
  
  ---
  -- Close spreadsheet
  ---
  
  reco_web_Functions.close_spreadsheet;
  
EXCEPTION
 WHEN others
 THEN
   htp.tableclose;
   htp.print('Report Exception Condition:'||sqlerrm|| -- CONTINUE HERE ADD TO OTHER FUNCTS
            ' Date:'||TO_CHAR(SYSDATE,'DD-MON-YYYY'));
   htp.htmlClose;
END; -- rstx_galv_rpt

--------------------------------------------------------------------------------
PROCEDURE rstx_shipcal_rpt
IS
BEGIN
  rstx_shipcal_rpt('4');
END;

--------------------------------------------------------------------------------
PROCEDURE rstx_shipcal_rpt(pi_QtyWeeks IN varchar2)
IS
BEGIN
  rstx_shipcal_rpt(pi_QtyWeeks,'F');
END;

--------------------------------------------------------------------------------
PROCEDURE rstx_shipcal_rpt(pi_QtyWeeks IN varchar2, pi_RoundToEndOfWeek IN varchar2)
IS
  vn_TmpHistId number;
BEGIN
  SELECT MAX(cutsch_hist_id) INTO vn_TmpHistId FROM reco_rstx_cutsch_hist;
  
  IF vn_TmpHistId IS NULL
  THEN
    reco_web_functions.reset_sheet;
    reco_web_functions.table_attr := 'border="1" frame="border" rules="all"';
--    reco_web_functions.open_spreadsheet; 
    reco_web_functions.open_spreadsheet('NODATE:reco_steel_shipments_report'); --Added by RS on 03/04/2026.
    reco_web_functions.col_span := 10;
    reco_web_functions.add_header_column(
      'Internal Error 2052 - History and Processing is Corrupted. Contact MIS.');
    reco_web_functions.print_header;
    reco_web_Functions.close_spreadsheet;
    RETURN;
  END IF;
  
  rstx_shipcal_rpt(pi_QtyWeeks,pi_RoundToEndOfWeek,TO_CHAR(vn_TmpHistId));
END;
--------------------------------------------------------------------------------
---------------------------------------------------------------------
-- Added by Komal 06-NOV-2025 : New version of Ship Calendar Report
-- Includes First Date parameter for date-range based extraction
---------------------------------------------------------------------
PROCEDURE rstx_shipcal_rpt_bydate(
   pi_QtyWeeks         IN VARCHAR2,
   pi_RoundToEndOfWeek IN VARCHAR2,
   pi_FirstDate        IN VARCHAR2)
IS
   vd_TransBeginDate DATE := TO_DATE(pi_FirstDate,'DD-MON-YYYY');
   vd_TransEndDate   DATE := vd_TransBeginDate + (pi_QtyWeeks * 7) - 1;

   vn_TmpHistId      NUMBER;
BEGIN
   -- Reuse same history id logic to keep consistent behavior
   SELECT MAX(cutsch_hist_id)
   INTO vn_TmpHistId
   FROM reco_rstx_cutsch_hist;

   IF vn_TmpHistId IS NULL THEN
      reco_web_functions.reset_sheet;
      reco_web_functions.table_attr := 'border="1" frame="border" rules="all"';
--      reco_web_functions.open_spreadsheet;  
	  IF NOT bSummaryReport THEN
	  	reco_web_functions.open_spreadsheet('NODATE:reco_steel_shipments_report'); --Added by RS on 03/04/2026.
	  ELSE
	  	reco_web_functions.open_spreadsheet('NODATE:reco_steel_shipments_summary_report'); --Added by RS on 03/04/2026.
	  END IF; 
      reco_web_functions.col_span := 10;
      reco_web_functions.add_header_column(
         'Internal Error 2052 - History and Processing is Corrupted. Contact MIS.');
      reco_web_functions.print_header;
      reco_web_Functions.close_spreadsheet;
      RETURN;
   END IF;

   -----------------------------------------------------------------
   -- Call base logic (with History ID version) but filter results
   -- by vd_TransBeginDate and vd_TransEndDate in the report query.
   -----------------------------------------------------------------
   rstx_shipcal_bydate_rpt(pi_QtyWeeks, pi_RoundToEndOfWeek, TO_CHAR(vn_TmpHistId),vd_TransBeginDate);

   DBMS_OUTPUT.put_line(
      'Ship Calendar report generated for period '
      || TO_CHAR(vd_TransBeginDate,'DD-MON-YYYY')
      || ' to '
      || TO_CHAR(vd_TransEndDate,'DD-MON-YYYY'));
      
         DBMS_OUTPUT.put_line(
      'Value passing in proc: '
      || pi_RoundToEndOfWeek
      || ' and '
      || vn_TmpHistId);
END rstx_shipcal_rpt_bydate;

--------------------------------------------------------------------------------
PROCEDURE rstx_shipcal_rpt_sum(pi_QtyWeeks IN varchar2, pi_RoundToEndOfWeek IN varchar2,pi_FirstDate IN varchar2) --added by Komal 06-NOV-25
IS
  
BEGIN
  -- Set the boolean  
  bSummaryReport := TRUE;
  
  --rstx_shipcal_rpt(pi_QtyWeeks,pi_RoundToEndOfWeek);
  rstx_shipcal_rpt_bydate(pi_QtyWeeks,pi_RoundToEndOfWeek,pi_FirstDate);--added by Komal 06-NOV-25
  bSummaryReport := FALSE;
  
END;

--------------------------------------------------------------------------------
PROCEDURE rstx_shipcal_bydate_rpt( pi_QtyWeeks IN varchar2,
                            pi_RoundToEndOfWeek IN varchar2,
                            pi_GivenHistId IN varchar2,
							pi_FirstDate IN VARCHAR2)
IS
  TYPE rec_SheetColumnInfo IS record
            ( rptColTypeCode varchar2(30),
              num_child_cols number,
              shipment_date reco_shipment.shipment_date%TYPE,
              tracking_number reco_shipment.tracking_number%TYPE,
              shipment_status reco_shipment.shipment_status%TYPE,
              shipment_id reco_shipment.shipment_id%TYPE,
              STATE reco_shipping_addresses_v.state%TYPE,
              daystrt_npb_tonn number,
              daystrt_spb_tonn number,
              daystrt_spg_tonn number,
              daystrt_dpb_tonn number,
              daystrt_dpg_tonn number,
              
              daystrt506_npb_tonn number,
              daystrt506_spb_tonn number,
              daystrt506_spg_tonn number,
              daystrt506_dpb_tonn number,
              daystrt506_dpg_tonn number,
              
              vcFirstNegativeDateText varchar2(30),
              
              ship_stlwgt number,
              ship_stlwgtDP number,
              ship_totwgt number,
              day_manuf_spb_tonn number,
              day_manuf_dpb_tonn number);
  
  TYPE coll_SheetColumnInfo IS TABLE OF rec_SheetColumnInfo;
  --oTheSheetColumnInfo coll_SheetColumnInfo; -- Fetched, so don't initialize
  oTheSheetColumnInfo coll_SheetColumnInfo := coll_SheetColumnInfo();
  oTheSheetColumnInfoSP coll_SheetColumnInfo := coll_SheetColumnInfo();
  oTheSheetColumnInfoDP coll_SheetColumnInfo := coll_SheetColumnInfo();
                                        -- Initialize since not fetched
  nCtrSheetColumnInfo number;
  thelocation   varchar2(80);
--  type rec_PartNameAndInv is record
--            ( n_partid reco_rstx_originvqty_hist.inventory_item_id%type,
--              n_partname reco_rstx_originvqty_hist.segment1%type,
--              n_partpunch reco_rstx_originvqty_hist.thepunch%type,
--              n_parttype reco_rstx_originvqty_hist.thetype%type,
--              n_partcoat reco_rstx_originvqty_hist.thecoat%type,
--              n_partnumlen reco_rstx_originvqty_hist.numlength%type,
--              n_partcharlen reco_rstx_originvqty_hist.charlength%type,
--              n_originvqty reco_rstx_originvqty_hist.quantity%type,
--              b_partid reco_rstx_originvqty_hist.inventory_item_id%type,
--              b_partname reco_rstx_originvqty_hist.segment1%type,
--              b_partpunch reco_rstx_originvqty_hist.thepunch%type,
--              b_parttype reco_rstx_originvqty_hist.thetype%type,
--              b_partcoat reco_rstx_originvqty_hist.thecoat%type,
--              b_partnumlen reco_rstx_originvqty_hist.numlength%type,
--              b_partcharlen reco_rstx_originvqty_hist.charlength%type,
--              b_originvqty reco_rstx_originvqty_hist.quantity%type,
--              g_partid reco_rstx_originvqty_hist.inventory_item_id%type,
--              g_partname reco_rstx_originvqty_hist.segment1%type,
--              g_partpunch reco_rstx_originvqty_hist.thepunch%type,
--              g_parttype reco_rstx_originvqty_hist.thetype%type,
--              g_partcoat reco_rstx_originvqty_hist.thecoat%type,
--              g_partnumlen reco_rstx_originvqty_hist.numlength%type,
--              g_partcharlen reco_rstx_originvqty_hist.charlength%type,
--              g_originvqty reco_rstx_originvqty_hist.quantity%type,
--              groupnumber number);
--  
--  type coll_PartNameAndInv is table of rec_PartNameAndInv;
--  --oThePartNameAndInv coll_PartNameAndInv; -- Fetched, so don't initialize
--  oThePartNameAndInv coll_PartNameAndInv := coll_PartNameAndInv();
--                                        -- Initialize since not fetched
--  --nCtrPartNameAndInv number;
  
  vn_WorkingHistId number;
  vc_WorkingHistUser reco_rstx_cutsch_hist.theusername%TYPE;
  vd_WorkingHistDate date;
  vn_MaxRecentHistId number;
  vc_MaxRecentHistUser reco_rstx_cutsch_hist.theusername%TYPE;
  vd_MaxRecentHistDate date;
  
  vr_Params reco_rstx_userparam_hist%ROWTYPE;
  
  vn_QtyColumnsInSpreadsheet number; -- This gets set when finding column info
  
  vc_Color_OddDayNorm varchar2(80);
  vc_Color_EvenDayNorm varchar2(80);
  vc_Color_BlackSteel varchar2(80);
  vc_Color_Negative varchar2(80);
  vc_Color_InvText varchar2(80);
  vc_Color_DelivStdTxt varchar2(80);
  
  vd_FirstDateShown date;
  vd_LastDateShown date;
 
-- ----------------------------------------------------------------------------- JNL FUNCTION START
-- -----------------------------------------------------------------------------
FUNCTION WeightForPartType ( p_shipmentId IN NUMBER,
                             p_partTypeToUse IN VARCHAR2)
RETURN number
IS
   sumTotal number;

   CURSOR c_getTotal IS
   SELECT SUM(subrspv.calc_tons) totwgt
   FROM   reco_shipment_parts_v subrspv
   WHERE  subrspv.SHIPMENT_ID  = p_shipmentId
     AND  subrspv.PART_NAME LIKE p_partTypeToUse ;

BEGIN

   OPEN c_getTotal;
   FETCH c_getTotal INTO sumTotal;

   IF c_getTotal%notfound THEN
      sumTotal := 0;
   END IF;

   CLOSE c_getTotal;

RETURN sumTotal;

EXCEPTION
WHEN OTHERS THEN
   raise_application_error(-20001,'An error was encountered - '||SQLCODE||' -ERROR- '||SQLERRM);
END;
-- -----------------------------------------------------------------------------
-- ----------------------------------------------------------------------------- JNL FUNCTION END  
  --vn_TmpDayCtr number;
BEGIN -- rstx_shipcal_rpt
  thelocation := 'begin';
  get_Reco_organization('0');  -- force to RECO US
  -- 
  -- Special History note:
  -- 
  -- We only use the HISTORY_ID in this method for calculating
  -- the PART ORIGINAL INVENTORY, and nothing else -- CONTINUE HERE
  -- 
  -- Try to grab the inventory from start of day
  -- (The cutschedule ID of user NIGHTLY AUTO REFRESH)
  -- 
  -- If that doesn't work then just use current inventory
  -- (still print an error so we know what happened)
  
  DECLARE
    vn_TmpQtyRows number;
  BEGIN
    SELECT COUNT(*) INTO vn_TmpQtyRows FROM reco_rstx_cutsch_hist;
    IF NVL(vn_TmpQtyRows,0) = 0
    THEN
      reco_web_functions.reset_sheet;
      reco_web_functions.table_attr := 'border="1" frame="border" rules="all"';
--      reco_web_functions.open_spreadsheet;   
	  IF NOT bSummaryReport THEN
	  	reco_web_functions.open_spreadsheet('NODATE:reco_steel_shipments_report'); --Added by RS on 03/04/2026.
	  ELSE
	  	reco_web_functions.open_spreadsheet('NODATE:reco_steel_shipments_summary_report'); --Added by RS on 03/04/2026.
	  END IF;
      reco_web_functions.col_span := 10;
      reco_web_functions.add_header_column(
        'Internal Error 2070 - Invalid History / Info. Contact MIS.');
      reco_web_functions.print_header;
      reco_web_Functions.close_spreadsheet;
      RETURN;
    END IF;
  END;
  
  SELECT cutsch_hist_id, thetime, theusername
  INTO vn_MaxRecentHistId, vd_MaxRecentHistDate, vc_MaxRecentHistUser
  FROM reco_rstx_cutsch_hist
  WHERE cutsch_hist_id IN
                  ( SELECT MAX(cutsch_hist_id)
                    FROM reco_rstx_cutsch_hist );
  
  vn_WorkingHistId := vn_MaxRecentHistId;
  vc_WorkingHistUser := vc_MaxRecentHistUser;
  vd_WorkingHistDate := TRUNC(vd_MaxRecentHistDate);
  
  ---
  -- Access user parameters
  ---
  
  BEGIN
    SELECT * INTO vr_Params
    FROM reco_rstx_userparam_hist WHERE cutsch_hist_id = vn_WorkingHistId;
    
    IF vr_Params.min_cut_allowed IS NULL
    OR vr_Params.max_cut_allowed IS NULL
    OR vr_Params.first_date_of_reqs IS NULL
    OR vr_Params.first_date_of_cutting IS NULL
    OR vr_Params.first_date_of_cutting < vr_Params.first_date_of_reqs
    THEN RAISE NO_DATA_FOUND;
    END IF;
    
    -- MARCH 2013 - Added to synch Excel report with Row number
    IF vr_Params.min_cut_allowed != 5
    THEN vr_Params.min_cut_allowed := 5;
    END IF;
  EXCEPTION
    WHEN others
    THEN
      reco_web_functions.reset_sheet;
      reco_web_functions.table_attr := 'border="1" frame="border" rules="all"';
--      reco_web_functions.open_spreadsheet;    
	  IF NOT bSummaryReport THEN
	  	reco_web_functions.open_spreadsheet('NODATE:reco_steel_shipments_report'); --Added by RS on 03/04/2026.
	  ELSE
	  	reco_web_functions.open_spreadsheet('NODATE:reco_steel_shipments_summary_report'); --Added by RS on 03/04/2026.
	  END IF;
      reco_web_functions.col_span := 10;
      reco_web_functions.add_header_column(
      'Internal Error 2031 - User params inaccessible. Contact MIS');
      reco_web_functions.print_header;
      reco_web_Functions.close_spreadsheet;
      RETURN;
  END;
  
  ---
  -- Determine cell colors
  ---
  
  vc_Color_OddDayNorm := 'bgcolor = #F7FFBB';
  vc_Color_EvenDayNorm := 'bgcolor = #B3FBBF';
  vc_Color_BlackSteel := 'bgcolor =#000000 <font color=WHITE';
  vc_Color_Negative := 'bgcolor =#FFFFFF <font color=RED';
  vc_Color_InvText := '<font color=BLUE';
  vc_Color_DelivStdTxt := 'bgcolor =#C0C0C0 <font color=BLACK';
  
  ---
  -- Determine first report date, last report date, and other parameters
  ---
  
  SELECT  MIN(calday.thedate) INTO vd_FirstDateShown
  FROM  reco_rstx_calday calday -- Good:see get_date_toshowin_rpt description
  WHERE   calday.thedate >= vr_Params.first_date_of_reqs
  AND     calday.thedate < vr_Params.first_date_of_cutting
  AND     EXISTS (SELECT  1
                  FROM  reco_truck rs,
                        reco_truckstop_parts rsp,
                        reco_rstx_originvqty_hist roiq
                  WHERE   roiq.inventory_item_id = rsp.part_id
                  AND     rsp.orig_subinventory_code = 'RSTX'
                  AND     rsp.stop_truck_id = rs.truck_id
                  AND     rs.truck_status IN ('A','H','B')
                  AND     rs.truck_date = calday.thedate
                  AND     roiq.cutsch_hist_id = vn_WorkingHistId);
  
  vd_FirstDateShown := NVL(vd_FirstDateShown,vr_Params.first_date_of_cutting);
  
  vd_LastDateShown :=
      vd_FirstDateShown + (TO_NUMBER(NVL(pi_QtyWeeks,2) * 7));
	  

      ---------------------------------------------------------------------
    -- Added by Komal 06-NOV-2025: Override logic if First Date provided
    ---------------------------------------------------------------------
 

       vd_FirstDateShown := pi_FirstDate;--vd_TransBeginDate;
       --vd_LastDateShown  := vd_TransEndDate;
        vd_LastDateShown :=
        vd_FirstDateShown + (TO_NUMBER(NVL(pi_QtyWeeks,2) * 7));
       DBMS_OUTPUT.PUT_LINE('First Date Override Active: ' ||
                            TO_CHAR(vd_FirstDateShown,'DD-MON-YYYY') || ' to ' ||
                            TO_CHAR(vd_LastDateShown,'DD-MON-YYYY'));
 
    ---------------------------------------------------------------------


  
  IF vd_FirstDateShown IS NULL OR vd_LastDateShown IS NULL
  THEN
    reco_web_functions.reset_sheet;
    reco_web_functions.table_attr := 'border="1" frame="border" rules="all"';
--    reco_web_functions.open_spreadsheet;   
	  IF NOT bSummaryReport THEN
	  	reco_web_functions.open_spreadsheet('NODATE:reco_steel_shipments_report'); --Added by RS on 03/04/2026.
	  ELSE
	  	reco_web_functions.open_spreadsheet('NODATE:reco_steel_shipments_summary_report'); --Added by RS on 03/04/2026.
	  END IF; 
    reco_web_functions.col_span := 10;
    reco_web_functions.add_header_column(
    'Internal Error 2045 - Date is invalid or corrupt. Contact MIS');
    reco_web_functions.print_header;
    reco_web_Functions.close_spreadsheet;
    RETURN;
  END IF;
  
  IF UPPER(pi_RoundToEndOfWeek) LIKE 'T%'
  THEN
    LOOP
      IF TO_CHAR(vd_LastDateShown,'DY') = 'SUN'
      THEN exit;
      END IF;
      
      vd_LastDateShown := vd_LastDateShown + 1;
    END LOOP;
  END IF;
  
  ---
  -- Set values for: reco_rstx_tmpshpcalparts
  -- (This table represents the part-row information in our spreadsheet)
  -- 
  -- NOTE #1 - PERFORMANCE
  -- We only need to refresh reco_rstx_tmpshpcalparts if the parts
  -- could have changed (e.g. the cutsch was refreshed)
  -- 
  -- NOTE #2
  -- This does not include any blank lines between rows
  ---
  
  DECLARE
    vb_ForceRptRefresh BOOLEAN;
    vn_PreviousCutSchHistId number;
  BEGIN
    
    vb_ForceRptRefresh := FALSE;
    
    BEGIN
      SELECT prev_rpt_cutsch_hist_id
      INTO vn_PreviousCutSchHistId
      FROM reco_rstx_lastshpcalrun;
    EXCEPTION
      WHEN NO_DATA_FOUND
      THEN
        vb_ForceRptRefresh := TRUE; 
        vn_PreviousCutSchHistId := -1;
      WHEN others
      THEN
        reco_web_functions.reset_sheet;
        reco_web_functions.table_attr := 'border="1" frame="border" rules="all"';
--        reco_web_functions.open_spreadsheet;           
		  IF NOT bSummaryReport THEN
		  	reco_web_functions.open_spreadsheet('NODATE:reco_steel_shipments_report'); --Added by RS on 03/04/2026.
		  ELSE
		  	reco_web_functions.open_spreadsheet('NODATE:reco_steel_shipments_summary_report'); --Added by RS on 03/04/2026.
		  END IF;
        reco_web_functions.col_span := 10;
        reco_web_functions.add_header_column(
          'Internal Error 2074 - Internal tracking '||
          'of reports is corrupted. Contact MIS');
        reco_web_functions.print_header;
        reco_web_Functions.close_spreadsheet;
        RETURN;
    END;
    
    IF vb_ForceRptRefresh = TRUE
    OR vn_WorkingHistId != vn_PreviousCutSchHistId
    THEN
      DELETE FROM reco_rstx_tmpshpcalparts;
      
      -- refresh the part records / table row information
      INSERT INTO reco_rstx_tmpshpcalparts
      ( N_PARTID,N_PARTNAME,N_PARTPUNCH,N_PARTTYPE,
        N_PARTCOAT,N_PARTNUMLEN,N_PARTCHARLEN,N_ORIGINVQTY,
        B_PARTID,B_PARTNAME,B_PARTPUNCH,B_PARTTYPE,
        B_PARTCOAT,B_PARTNUMLEN,B_PARTCHARLEN,B_ORIGINVQTY,
        G_PARTID,G_PARTNAME,G_PARTPUNCH,G_PARTTYPE,
        G_PARTCOAT,G_PARTNUMLEN,G_PARTCHARLEN,G_ORIGINVQTY,
        SORTORDER
      )
      (
        SELECT  nopunroiq.inventory_item_id n_partid,
                NVL(nopunroiq.segment1,'N'||galvroiq.thetype||
                                       'B'||galvroiq.charlength) n_partname,
                NVL(nopunroiq.thepunch,'N') n_partpunch,
                NVL(nopunroiq.thetype,galvroiq.thetype) n_parttype,
                NVL(nopunroiq.thecoat,'B') n_partcoat,
                NVL(nopunroiq.numlength,galvroiq.numlength) n_partnumlen,
                NVL(nopunroiq.charlength,galvroiq.charlength) n_partcharlen,
                NVL(nopunroiq.quantity,0) n_originvqty,
                blackroiq.inventory_item_id b_partid,
                NVL(blackroiq.segment1,galvroiq.thepunch||galvroiq.thetype||
                                       'B'||galvroiq.charlength) b_partname,
                NVL(blackroiq.thepunch,'N') b_partpunch,
                NVL(blackroiq.thetype,galvroiq.thetype) b_parttype,
                NVL(blackroiq.thecoat,'B') b_partcoat,
                NVL(blackroiq.numlength,galvroiq.numlength) b_partnumlen,
                NVL(blackroiq.charlength,galvroiq.charlength) b_partcharlen,
                NVL(blackroiq.quantity,0) b_originvqty,
                galvroiq.inventory_item_id g_partid,
                galvroiq.segment1 g_partname,
                galvroiq.thepunch g_partpunch,
                galvroiq.thetype g_parttype,
                galvroiq.thecoat g_partcoat,
                galvroiq.numlength g_partnumlen,
                galvroiq.charlength g_partcharlen,
                galvroiq.quantity g_originvqty,
                CASE
                  WHEN galvroiq.thepunch = 'S'
                  AND galvroiq.thetype = '504'                             
                  AND galvroiq.numlength >= vr_Params.min_cut_allowed
                  AND galvroiq.numlength <= vr_Params.max_cut_allowed
                  THEN 1
                  WHEN galvroiq.thepunch = 'D'
                  AND galvroiq.thetype = '504'                             
                  AND galvroiq.numlength >= vr_Params.min_cut_allowed
                  AND galvroiq.numlength <= vr_Params.max_cut_allowed
                  THEN 2
                  WHEN galvroiq.thepunch = 'S'
                  AND galvroiq.thetype = '506'                             
                  AND galvroiq.numlength >= vr_Params.min_cut_allowed
                  AND galvroiq.numlength <= vr_Params.max_cut_allowed
                  THEN 3
                  WHEN galvroiq.thepunch = 'D'
                  AND galvroiq.thetype = '506'                             
                  AND galvroiq.numlength >= vr_Params.min_cut_allowed
                  AND galvroiq.numlength <= vr_Params.max_cut_allowed
                  THEN 4
                  ELSE 5
                END sortorder
        FROM  reco_rstx_originvqty_hist nopunroiq,
              reco_rstx_originvqty_hist blackroiq,
              reco_rstx_originvqty_hist galvroiq
        WHERE   galvroiq.category_set_id = nCSetG
        AND     galvroiq.inventory_item_id IS NOT NULL
        AND     galvroiq.cutsch_hist_id = vn_WorkingHistId
        AND     galvroiq.actual_attribute4 = blackroiq.segment1 (+)
        AND     blackroiq.category_set_id (+) = nCSetB
        AND     blackroiq.cutsch_hist_id (+) = vn_WorkingHistId
        AND     'N'||galvroiq.thetype||'B'||galvroiq.charlength
                              = nopunroiq.segment1 (+)
        AND     nopunroiq.category_set_id (+) = nCSetN
        AND     nopunroiq.cutsch_hist_id (+) = vn_WorkingHistId
      );
      
      COMMIT;
    END IF;
  END;
  thelocation := 'refresh';  
  ---
  -- Cache our current cutsch_hist_id into reco_rstx_lastshpcalrun table
  ---
  
  DECLARE
    vn_TmpNumRows number; -- Should always be 1
  BEGIN
    UPDATE reco_rstx_lastshpcalrun
    set prev_rpt_cutsch_hist_id = vn_WorkingHistId;
    
    vn_TmpNumRows := SQL%ROWCOUNT;
    
    IF vn_TmpNumRows > 1
    THEN
      reco_web_functions.reset_sheet;
      reco_web_functions.table_attr := 'border="1" frame="border" rules="all"';
--      reco_web_functions.open_spreadsheet;   
	  IF NOT bSummaryReport THEN
	  	reco_web_functions.open_spreadsheet('NODATE:reco_steel_shipments_report'); --Added by RS on 03/04/2026.
	  ELSE
	  	reco_web_functions.open_spreadsheet('NODATE:reco_steel_shipments_summary_report'); --Added by RS on 03/04/2026.
	  END IF;
      reco_web_functions.col_span := 10;
      reco_web_functions.add_header_column(
        'Internal Error 2075 - Caching Table is corrupted. Contact MIS');
      reco_web_functions.print_header;
      reco_web_Functions.close_spreadsheet;
      RETURN;
    ELSIF vn_TmpNumRows = 0
    THEN
      INSERT INTO reco_rstx_lastshpcalrun(prev_rpt_cutsch_hist_id)
      VALUES (vn_WorkingHistId);
    END IF;
    
    COMMIT;
  END;  
    thelocation := 'lastrun';
  ---
  -- Set values for: oTheSheetColumnInfo
  -- 
  -- The values in oTheSheetColumnInfo represent each cell in the
  -- 2nd row of the spreadsheet (the row with shipment names in it)
  -- 
  -- Determine Report Column information: days / shipments / inventory numbers
  -- Order is similar to:
  -- PARTNAME
  --        ->
  --      Repeat(DAILYPARTINV -> DELIVEREDSHIP -> PENDINGSHIP -> DAYPARTPROPOSEDMFG)
  --            ->
  --                ENDINVTOTAL
  ---
  
  ---
  -- And vn_QtyColumnsInSpreadsheet gets set as well
  ---

  DECLARE
    CURSOR cur_ColData (pi_FirstDate IN date,
                        pi_LastDate IN date,
                        pi_CurHistoryId IN number,
                        pi_sortOrder IN NUMBER, pi_sortOrder2 IN NUMBER, 
                        pi_sortorder3 number, pi_sortorder4 number, pi_sortorder5 number)        -- JNL
    IS
      -- Retreive a spot in collection for PartName (first column spot)
      SELECT  1 sort_OverallLayout,
              NULL shipment_date,
              NULL sort_DayInvQty_Ship_Mfg,
              NULL sort_DelivShip_Or_Not,
              'PARTNAME' rptColTypeCode, 
              ' ' vcFirstNegativeDateText,
              1 num_child_cols,
              NULL tracking_number,
              NULL shipment_status,
              NULL shipment_id,
              NULL STATE,
              NULL ship_stlwgt,
              NULL ship_stlwgtDP,
              NULL ship_totwgt
      FROM  dual
      -- Retreive a spot for INV label on each date (each date's INV column)
      UNION
      SELECT  2 sort_OverallLayout,
              calday.thedate shipment_date,
              1 sort_DayInvQty_Ship_Mfg,
              NULL sort_DelivShip_Or_Not,
              'DAILYPARTINV' rptColTypeCode, 
              ' ' vcFirstNegativeDateText,
              CASE
              WHEN calday.thedate = pi_FirstDate
              THEN 3
              ELSE 2
              END num_child_cols,
              NULL tracking_number,
              NULL shipment_status,
              NULL shipment_id,
              NULL STATE,
              NULL ship_stlwgt,
              NULL ship_stlwgtDP,
              NULL ship_totwgt
      FROM  reco_rstx_calday calday -- Good:see get_date_toshowin_rpt description
      WHERE   calday.thedate >= pi_FirstDate
      AND     calday.thedate <= pi_LastDate
      -- Retreive a spot for each day's DELIVERED shipments
      UNION
      SELECT  /*+ USE_NL( rs,rsav,subQSteelWgt,subQTotWgt) */ 2 sort_OverallLayout,
              rs.truck_date shipment_date,
              2 sort_DayInvQty_Ship_Mfg,
              1 sort_DelivShip_Or_Not,
              'DELIVEREDSHIP' rptColTypeCode, 
              ' ' vcFirstNegativeDateText,
              2 num_child_cols,
              NVL(rs.tracking_number,rsav.stop_identifier) tracking_number,
              rs.truck_status shipment_status,
              rsav.shipment_id shipment_id,
              rsav.state STATE,
              subQSteelWgt.stlwgt ship_stlwgt,
              subQSteelWgt.stlwgt ship_stlwgtDP,
              subQTotWgt.totwgt ship_totwgt
      FROM  reco_truck rs,
            reco_truckstop_v rsav,
            (
              SELECT  /*+ USE_NL( subrs,ts,subrsp,subQPartsToSum) */ ts.shipment_id,
                      SUM(subrsp.calc_tons) stlwgt
              FROM  reco_truckstop ts, reco_truckstop_parts subrsp,
                    reco_truck subrs,
                    (
                      SELECT n_partid partid FROM reco_rstx_tmpshpcalparts
                      WHERE sortorder IN (1,2,3,4,5)  -- JNL TEST in 1 -- (1,2)
                      UNION
                      SELECT b_partid partid FROM reco_rstx_tmpshpcalparts
                      WHERE sortorder IN (1,2,3,4,5)  -- JNL TEST in 1 -- (1,2)
                      UNION
                      SELECT g_partid partid FROM reco_rstx_tmpshpcalparts
                      WHERE sortorder IN (1,2,3,4,5)  -- JNL TEST in 1 -- (1,2)
                    ) subQPartsToSum -- Verify part relevancy
              WHERE   subrs.truck_id = ts.stop_truck_id
              AND     subrsp.stop_truck_id = ts.stop_truck_id
              AND     subrsp.stop_order_id = ts.stop_order_id
              AND     subrsp.part_id = subQPartsToSum.partid
              AND     subrs.truck_date >= TO_DATE('22-sep-20')
              AND     subrs.truck_date <= TO_DATE('05-oct-20')
              AND     subrs.truck_status IN ('D')
              AND     subrsp.orig_subinventory_code = 'RSTX'
              --and     subroiq.cutsch_hist_id = pi_CurHistoryId
              GROUP BY  ts.shipment_id
            ) subQSteelWgt,
            (
              SELECT  /*+ USE_NL( subrs,ts,subrsp,submsib ) */ ts.shipment_id,
                      SUM(subrsp.calc_tons) totwgt
             FROM  reco_truckstop ts, reco_truckstop_parts subrsp,
                   reco_truck subrs,
                    apps.mtl_system_items_b_kfv submsib
                        -- do not use reco_rstx_originvqty_hist here, cause we need
                        -- ALL parts, and not just steel parts for the total weight
              WHERE   subrs.truck_id = ts.stop_truck_id
              AND    subrsp.stop_truck_id = ts.stop_Truck_id
              AND    subrsp.stop_order_id = ts.stop_order_id
              AND     subrsp.part_id = submsib.inventory_item_id AND submsib.organization_id = 0
              AND     subrs.truck_date >= pi_FirstDate
              AND     subrs.truck_date <= pi_LastDate
              AND     subrs.truck_status IN ('D')
              AND     submsib.inventory_item_status_code = 'Active'
              GROUP BY  ts.shipment_id
            ) subQTotWgt
      WHERE   rs.truck_id = rsav.stop_truck_id
      AND     rsav.shipment_id = subQSteelWgt.shipment_id
      AND     rsav.shipment_id = subQTotWgt.shipment_id
      AND     rs.truck_date >= pi_FirstDate
      AND     rs.truck_date <= pi_LastDate
      AND     rs.truck_status IN ('D')
      AND     EXISTS (SELECT /* USE_NL( roiq,rsp ) */ 'Y'
                      FROM  reco_truckstop ts, reco_truckstop_parts rsp,
                            reco_rstx_originvqty_hist roiq
                      WHERE   rsav.shipment_id = ts.shipment_id
                      AND     rsp.stop_truck_id = ts.stop_truck_id
                      AND     rsp.stop_order_id = ts.stop_order_id
                      AND     rsp.part_id = roiq.inventory_item_id
                      AND     rsp.orig_subinventory_code = 'RSTX'
                      AND     roiq.cutsch_hist_id = pi_CurHistoryId)
      -- Retreive a spot for each day's PENDING shipments
      UNION
      SELECT  2 sort_OverallLayout,
              rs.truck_date shipment_date,
              2 sort_DayInvQty_Ship_Mfg,
              2 sort_DelivShip_Or_Not,
              'PENDINGSHIP' rptColTypeCode, 
              ' ' vcFirstNegativeDateText,
              2 num_child_cols,
              NVL(rs.tracking_number,rsav.stop_identifier) tracking_number,
              rs.truck_status shipment_status,
              rsav.shipment_id shipment_id,
              rsav.state STATE,
              subQSteelWgt.stlwgt ship_stlwgt,
              subQSteelWgt.stlwgt ship_stlwgtDP,
              subQTotWgt.totwgt ship_totwgt
      FROM  reco_truck rs,
            reco_truckstop_v rsav,
            (
              SELECT  /*+ USE_NL(subrs,ts,subrsp,subqpartstosum) */ts.shipment_id,
                      SUM(subrsp.calc_tons) stlwgt
              FROM  reco_truckstop ts, reco_truckstop_parts subrsp,
                    reco_truck subrs,
                    (
                      SELECT n_partid partid FROM reco_rstx_tmpshpcalparts
                      WHERE sortorder IN (pi_sortOrder , pi_sortOrder2, pi_sortorder3, pi_sortorder4,pi_sortorder5)  -- JNL TEST in 1 -- (1,2)
                      UNION
                      SELECT b_partid partid FROM reco_rstx_tmpshpcalparts
                      WHERE sortorder IN (pi_sortOrder , pi_sortOrder2, pi_sortorder3, pi_sortorder4,pi_sortorder5)  -- JNL TEST in 1 -- (1,2)
                      UNION
                      SELECT g_partid partid FROM reco_rstx_tmpshpcalparts
                      WHERE sortorder IN (pi_sortOrder , pi_sortOrder2, pi_sortorder3, pi_sortorder4,pi_sortorder5)  -- JNL TEST in 1 -- (1,2)
                    ) subQPartsToSum -- Verify part relevancy
              WHERE   subrs.truck_id = ts.stop_truck_id
              AND     subrsp.stop_truck_id = ts.stop_truck_id
              AND     subrsp.stop_order_id = ts.stop_order_id
              AND     subrsp.part_id = subQPartsToSum.partid
              AND     subrs.truck_date >= pi_FirstDate
              AND     subrs.truck_date <= pi_LastDate
              AND     subrs.truck_status IN ('A','H','B')
              AND     subrsp.orig_subinventory_code = 'RSTX'
              GROUP BY  ts.shipment_id
            ) subQSteelWgt,
            (
              SELECT  /*+ USE_NL( subrs,ts,subrsp,submsib ) */ts.shipment_id,
                      SUM(subrsp.calc_tons) totwgt
              FROM  reco_truckstop ts, reco_truckstop_parts subrsp,
                    reco_truck subrs,
                    apps.mtl_system_items_b_kfv submsib
                        -- do not use reco_rstx_originvqty_hist here, cause we need
                        -- ALL parts, and not just steel parts for the total weight
              WHERE   subrs.truck_id = ts.stop_truck_id
              AND     subrsp.stop_Truck_id = ts.stop_truck_id
              AND     subrsp.stop_order_id = ts.stop_order_id
              AND     subrsp.part_id = submsib.inventory_item_id AND submsib.organization_id = 0
              AND     subrs.truck_date >= pi_FirstDate
              AND     subrs.truck_date <= pi_LastDate
              AND     subrs.truck_status IN ('A','H','B')
              AND     submsib.inventory_item_status_code = 'Active'
              GROUP BY  ts.shipment_id
            ) subQTotWgt
      WHERE   rs.truck_id = rsav.stop_truck_id
      AND     rsav.shipment_id = subQSteelWgt.shipment_id
      AND     rsav.shipment_id = subQTotWgt.shipment_id
      AND     rs.truck_date >= pi_FirstDate
      AND     rs.truck_date <= pi_LastDate
      AND     rs.truck_status IN ('A','H','B')
      AND     EXISTS (SELECT /*+ USE_NL( roiq, ts, rsp ) */'Y'
                      FROM  reco_truckstop ts, reco_truckstop_parts rsp,
                            reco_rstx_originvqty_hist roiq
                      WHERE   rsav.shipment_id = ts.shipment_id
                      AND     rsp.part_id = roiq.inventory_item_id
                      AND     rsp.orig_subinventory_code = 'RSTX'
                      AND     roiq.cutsch_hist_id = pi_CurHistoryId)
      -- Retreive a spot for each day's proposed MANUFACTING totals           -- JNL STEEL MANUF COMMENTED
--      union
--      select  2 sort_OverallLayout,
--              calday.thedate shipment_date,
--              3 sort_DayInvQty_Ship_Mfg,
--              null sort_DelivShip_Or_Not,
--              'DAYPARTPROPOSEDMFG' rptColTypeCode,
--              1 num_child_cols,
--              null tracking_number,
--              null shipment_status,
--              null shipment_id,
--              null state,
--              null ship_stlwgt,
--              null ship_stlwgtDP,
--              null ship_totwgt
--      from  reco_rstx_calday calday -- Good:see get_date_toshowin_rpt description
--      where   calday.thedate >= pi_FirstDate
--      and     calday.thedate <= pi_LastDate
      -- Retreive a spot in collection for Final Inv Qty (last column spot)
      UNION
      SELECT  3 sort_OverallLayout,
              NULL shipment_date,
              NULL sort_DayInvQty_Ship_Mfg,
              NULL sort_DelivShip_Or_Not,
              'ENDINVTOTAL' rptColTypeCode, 
              ' ' vcFirstNegativeDateText,
              2 num_child_cols,
              NULL tracking_number,
              NULL shipment_status,
              NULL shipment_id,
              NULL STATE,
              NULL ship_stlwgt,
              NULL ship_stlwgtDP,
              NULL ship_totwgt
      FROM  dual
--      order by  sort_OverallLayout,         -- JNL COMMENT START -- V9.0
--                shipment_date,
--                sort_DayInvQty_Ship_Mfg,
--                sort_DelivShip_Or_Not,
--                tracking_number,
--                shipment_id;                -- JNL COMMENT END -- V9.0
      UNION                                   -- JNL CODE START -- V9.0
      SELECT  3 sort_OverallLayout,
              NULL shipment_date,
              NULL sort_DayInvQty_Ship_Mfg,
              NULL sort_DelivShip_Or_Not,
              'NEGATIVEINV' rptColTypeCode, 
              ' ' vcFirstNegativeDateText,
              2 num_child_cols,
              NULL tracking_number,
              NULL shipment_status,
              NULL shipment_id,
              NULL STATE,
              NULL ship_stlwgt,
              NULL ship_stlwgtDP,
              NULL ship_totwgt
      FROM  dual
      ORDER BY  sort_OverallLayout,
                shipment_date,
                sort_DayInvQty_Ship_Mfg,
                sort_DelivShip_Or_Not,
                tracking_number,
                shipment_id;                  -- JNL CODE END -- V9.0
            
                
  BEGIN
    vn_QtyColumnsInSpreadsheet := 0;
  thelocation := 'sheetstore';    
    FOR rec_ColData
    IN cur_ColData (vd_FirstDateShown,vd_LastDateShown,vn_WorkingHistId, 1, 2, 3, 4,5)
    LOOP
      oTheSheetColumnInfo.extend(1);
  thelocation := 'sheetstore'||rec_ColData.shipment_id;   
      
      oTheSheetColumnInfo(oTheSheetColumnInfo.count).rptColTypeCode
              := rec_ColData.rptColTypeCode;
      oTheSheetColumnInfo(oTheSheetColumnInfo.count).num_child_cols
              := rec_ColData.num_child_cols;
      oTheSheetColumnInfo(oTheSheetColumnInfo.count).shipment_date
              := rec_ColData.shipment_date;
      oTheSheetColumnInfo(oTheSheetColumnInfo.count).tracking_number
              := rec_ColData.tracking_number;
      oTheSheetColumnInfo(oTheSheetColumnInfo.count).shipment_status
              := rec_ColData.shipment_status;
      oTheSheetColumnInfo(oTheSheetColumnInfo.count).shipment_id
              := rec_ColData.shipment_id;
      oTheSheetColumnInfo(oTheSheetColumnInfo.count).STATE
              := rec_ColData.state;
      oTheSheetColumnInfo(oTheSheetColumnInfo.count).daystrt_npb_tonn
              := NULL;
      oTheSheetColumnInfo(oTheSheetColumnInfo.count).daystrt_spb_tonn
              := NULL;
      oTheSheetColumnInfo(oTheSheetColumnInfo.count).daystrt_spg_tonn
              := NULL;
      oTheSheetColumnInfo(oTheSheetColumnInfo.count).daystrt_dpb_tonn
              := NULL;
      oTheSheetColumnInfo(oTheSheetColumnInfo.count).daystrt_dpg_tonn
              := NULL;
      oTheSheetColumnInfo(oTheSheetColumnInfo.count).daystrt506_npb_tonn
              := NULL;
      oTheSheetColumnInfo(oTheSheetColumnInfo.count).daystrt506_spb_tonn
              := NULL;
      oTheSheetColumnInfo(oTheSheetColumnInfo.count).daystrt506_spg_tonn
              := NULL;
      oTheSheetColumnInfo(oTheSheetColumnInfo.count).daystrt506_dpb_tonn
              := NULL;
      oTheSheetColumnInfo(oTheSheetColumnInfo.count).daystrt506_dpg_tonn        
              := NULL;
      oTheSheetColumnInfo(oTheSheetColumnInfo.count).vcFirstNegativeDateText
              := rec_ColData.vcFirstNegativeDateText;
      oTheSheetColumnInfo(oTheSheetColumnInfo.count).ship_stlwgt
              := rec_ColData.ship_stlwgt;
      oTheSheetColumnInfo(oTheSheetColumnInfo.count).ship_stlwgtDP
              := rec_ColData.ship_stlwgtDP;
      oTheSheetColumnInfo(oTheSheetColumnInfo.count).ship_totwgt
              := rec_ColData.ship_totwgt;
      oTheSheetColumnInfo(oTheSheetColumnInfo.count).day_manuf_spb_tonn
              := NULL;
      oTheSheetColumnInfo(oTheSheetColumnInfo.count).day_manuf_dpb_tonn
              := NULL;
      
      vn_QtyColumnsInSpreadsheet :=
        vn_QtyColumnsInSpreadsheet + rec_ColData.num_child_cols;
  END LOOP;
    
  END;
    thelocation := 'endstore';
-- ************************************************************************************* JNL TEST  END  
  
  DECLARE
    -- Selects all the numbers we will need for inventory-tonnage
    -- totals on a given day.
    -- Note#1 - When in doubt, assume SinglePunch is root table (over galv)
    -- Note#2 - When in doubt, assume Galv is root table (over black/nopunch)
    CURSOR cur_TonnagesForRptDate (pi_DesiredDay IN date, 
                                   pi_sortOrder IN NUMBER, pi_sortOrder2 IN NUMBER)
    IS
      SELECT  rptGrp1Parts.n_originvqty npb_originvqty,
              msibGrp1NoPun.unit_weight npb_unit_weight,
              msibGrp1NoPun.weight_uom_code npb_weight_uom_code,
              rptGrp1Parts.b_originvqty spb_originvqty,
              msibGrp1Black.unit_weight spb_unit_weight,
              msibGrp1Black.weight_uom_code spb_weight_uom_code,
              rptGrp1Parts.g_originvqty spg_originvqty,
              msibGrp1Galv.unit_weight spg_unit_weight,
              msibGrp1Galv.weight_uom_code spg_weight_uom_code,
              
              NVL(rptGrp2Parts.b_originvqty,0) dpb_originvqty,
              NVL(msibGrp2Black.unit_weight,0) dpb_unit_weight,
              NVL(msibGrp2Black.weight_uom_code,'LB') dpb_weight_uom_code,
              NVL(rptGrp2Parts.g_originvqty,0) dpg_originvqty,
              NVL(msibGrp2Galv.unit_weight,0) dpg_unit_weight,
              NVL(msibGrp2Galv.weight_uom_code,'LB') dpg_weight_uom_code,
              
              NVL(subQGrp1BlackShippedQty.totalPcs,0) spb_ship_cumm_qty,
              NVL(subQGrp1GalvShippedQty.totalPcs,0) spg_ship_cumm_qty,
              NVL(subQGrp1BlackMfgDailyQty.totalPcs,0) spb_newpun_today_qty,
              NVL(subQGrp1BlackMfgCummQty.totalPcs,0) spb_newpun_cumm_qty,
                            
              NVL(subQGrp2BlackShippedQty.totalPcs,0) dpb_ship_cumm_qty,
              NVL(subQGrp2GalvShippedQty.totalPcs,0) dpg_ship_cumm_qty,
              NVL(subQGrp2BlackMfgDailyQty.totalPcs,0) dpb_newpun_today_qty,
              NVL(subQGrp2BlackMfgCummQty.totalPcs,0) dpb_newpun_cumm_qty
                            
      FROM  reco_rstx_tmpshpcalparts rptGrp1Parts,
            reco_rstx_tmpshpcalparts rptGrp2Parts,
            apps.mtl_system_items_b_kfv msibGrp1NoPun,
            apps.mtl_system_items_b_kfv msibGrp1Black,
            apps.mtl_system_items_b_kfv msibGrp1Galv,
            apps.mtl_system_items_b_kfv msibGrp2Black,
            apps.mtl_system_items_b_kfv msibGrp2Galv,
        
            (
              SELECT  subparts.b_partid,
                      SUM(subrsp.quantity) totalPcs
              FROM  reco_truck subrs,
                    reco_truckstop_parts_v subrsp,
                    reco_rstx_tmpshpcalparts subparts
              WHERE   subrsp.stop_truck_id = subrs.truck_id
              AND     subrsp.part_id = subparts.b_partid
              AND     subrs.truck_date >= vd_FirstDateShown
              AND     subrs.truck_date < pi_DesiredDay
              AND     subrs.truck_status
                        -- Note: Rpt shows deliviered for today and future
                        IN ('A','H','B','D')
              AND     subrsp.orig_subinventory_code = 'RSTX'
              AND     subparts.sortorder IN (pi_sortOrder, pi_sortOrder2)
              GROUP BY  subparts.b_partid
            ) subQGrp1BlackShippedQty,

            (
              SELECT  subparts.g_partid,
                      SUM(subrsp.quantity) totalPcs
              FROM  reco_truck subrs,
                    reco_truckstop_parts_v subrsp,
                    reco_rstx_tmpshpcalparts subparts
              WHERE   subrsp.stop_truck_id = subrs.truck_id
              AND     subrsp.part_id = subparts.g_partid
              AND     subrs.truck_date >= vd_FirstDateShown
              AND     subrs.truck_date < pi_DesiredDay
              AND     subrs.truck_status
                        -- Note: Rpt shows deliviered for today and future
                        IN ('A','H','B','D')
              AND     subrsp.orig_subinventory_code = 'RSTX'
              AND     subparts.sortorder IN (pi_sortOrder, pi_sortOrder2)
              GROUP BY  subparts.g_partid
            ) subQGrp1GalvShippedQty,

            (
              SELECT  subparts.b_partid,
                      SUM(punrunhist.qty_bars_processed) totalPcs
              FROM  reco_rstx_calday calday,
                              -- Good:get_date_toshowin_rpt description
                    reco_rstx_punrun_hist punrunhist,
                    (
                      SELECT DISTINCT
                              subasg.punrun_id,
                              subreq.reqlength,
                              subreq.reqtype,
                              subreq.reqpunch
                              --NOTE: We do not care about PunchSch coating
                              --      because for this report we label all
                              --      punching results as black pieces
                      FROM  reco_rstx_punrun_hist subrun,
                            reco_rstx_punreq_hist subreq,
                            reco_rstx_punasg_hist subasg
                      WHERE   subrun.punrun_id = subasg.punrun_id
                      AND     subasg.punreq_id = subreq.punreq_id
                      AND     subrun.cutsch_hist_id = vn_WorkingHistId
                      AND     subasg.cutsch_hist_id = vn_WorkingHistId
                      AND     subreq.cutsch_hist_id = vn_WorkingHistId
                    ) subQPartData,
                    reco_rstx_tmpshpcalparts subparts
              WHERE   calday.thedate = pi_DesiredDay
              AND     calday.calday_id = punrunhist.calday_id
              AND     punrunhist.cutsch_hist_id = vn_WorkingHistId
              AND     punrunhist.punrun_id = subQPartData.punrun_id
              AND     subQPartData.reqlength = subparts.b_partnumlen
              AND     subQPartData.reqtype = subparts.b_parttype
              AND     subQPartData.reqpunch = subparts.b_partpunch
              AND     subparts.sortorder IN (pi_sortOrder, pi_sortOrder2)
              GROUP BY  subparts.b_partid
            ) subQGrp1BlackMfgDailyQty,

            (
              SELECT  subparts.b_partid,
                      SUM(punrunhist.qty_bars_processed) totalPcs
              FROM  reco_rstx_calday calday,
                              -- Good:get_date_toshowin_rpt description
                    reco_rstx_punrun_hist punrunhist,
                    (
                      SELECT DISTINCT
                              subasg.punrun_id,
                              subreq.reqlength,
                              subreq.reqtype,
                              subreq.reqpunch
                              --NOTE: We do not care about PunchSch coating
                              --      because for this report we label all
                              --      punching results as black pieces
                      FROM  reco_rstx_punrun_hist subrun,
                            reco_rstx_punreq_hist subreq,
                            reco_rstx_punasg_hist subasg
                      WHERE   subrun.punrun_id = subasg.punrun_id
                      AND     subasg.punreq_id = subreq.punreq_id
                      AND     subrun.cutsch_hist_id = vn_WorkingHistId
                      AND     subasg.cutsch_hist_id = vn_WorkingHistId
                      AND     subreq.cutsch_hist_id = vn_WorkingHistId
                    ) subQPartData,
                    reco_rstx_tmpshpcalparts subparts
              WHERE   calday.thedate >= vd_FirstDateShown
              AND     calday.thedate < pi_DesiredDay
              AND     calday.calday_id = punrunhist.calday_id
              AND     punrunhist.cutsch_hist_id = vn_WorkingHistId
              AND     punrunhist.punrun_id = subQPartData.punrun_id
              AND     subQPartData.reqlength = subparts.b_partnumlen
              AND     subQPartData.reqtype = subparts.b_parttype
              AND     subQPartData.reqpunch = subparts.b_partpunch
              AND     subparts.sortorder IN (pi_sortOrder, pi_sortOrder2)
              GROUP BY  subparts.b_partid
            ) subQGrp1BlackMfgCummQty,

            (
              SELECT  subparts.b_partid,
                      SUM(subrsp.quantity) totalPcs
              FROM  reco_truck subrs,
                    reco_truckstop_parts_v subrsp,
                    reco_rstx_tmpshpcalparts subparts
              WHERE   subrsp.stop_truck_id = subrs.truck_id
              AND     subrsp.part_id = subparts.b_partid
              AND     subrs.truck_date >= vd_FirstDateShown
              AND     subrs.truck_date < pi_DesiredDay
              AND     subrs.truck_status
                        -- Note: Rpt shows deliviered for today and future
                        IN ('A','H','B','D')
              AND     subrsp.orig_subinventory_code = 'RSTX'
              AND     subparts.sortorder IN (pi_sortOrder, pi_sortOrder2)
              GROUP BY  subparts.b_partid
            ) subQGrp2BlackShippedQty,

            (
              SELECT  subparts.g_partid,
                      SUM(subrsp.quantity) totalPcs
              FROM  reco_truck subrs,
                    reco_truckstop_parts_v subrsp,
                    reco_rstx_tmpshpcalparts subparts
              WHERE   subrsp.stop_truck_id = subrs.truck_id
              AND     subrsp.part_id = subparts.g_partid
              AND     subrs.truck_date >= vd_FirstDateShown
              AND     subrs.truck_date < pi_DesiredDay
              AND     subrs.truck_status
                        -- Note: Rpt shows deliviered for today and future
                        IN ('A','H','B','D')
              AND     subrsp.orig_subinventory_code = 'RSTX'
              AND     subparts.sortorder IN (pi_sortOrder, pi_sortOrder2)
              GROUP BY  subparts.g_partid
            ) subQGrp2GalvShippedQty,

            (
              SELECT  subparts.b_partid,
                      SUM(punrunhist.qty_bars_processed) totalPcs
              FROM  reco_rstx_calday calday,
                              -- Good:get_date_toshowin_rpt description
                    reco_rstx_punrun_hist punrunhist,
                    (
                      SELECT DISTINCT
                              subasg.punrun_id,
                              subreq.reqlength,
                              subreq.reqtype,
                              subreq.reqpunch
                              --NOTE: We do not care about PunchSch coating
                              --      because for this report we label all
                              --      punching results as black pieces
                      FROM  reco_rstx_punrun_hist subrun,
                            reco_rstx_punreq_hist subreq,
                            reco_rstx_punasg_hist subasg
                      WHERE   subrun.punrun_id = subasg.punrun_id
                      AND     subasg.punreq_id = subreq.punreq_id
                      AND     subrun.cutsch_hist_id = vn_WorkingHistId
                      AND     subasg.cutsch_hist_id = vn_WorkingHistId
                      AND     subreq.cutsch_hist_id = vn_WorkingHistId
                    ) subQPartData,
                    reco_rstx_tmpshpcalparts subparts
              WHERE   calday.thedate = pi_DesiredDay
              AND     calday.calday_id = punrunhist.calday_id
              AND     punrunhist.cutsch_hist_id = vn_WorkingHistId
              AND     punrunhist.punrun_id = subQPartData.punrun_id
              AND     subQPartData.reqlength = subparts.b_partnumlen
              AND     subQPartData.reqtype = subparts.b_parttype
              AND     subQPartData.reqpunch = subparts.b_partpunch
              AND     subparts.sortorder IN (pi_sortOrder, pi_sortOrder2)
              GROUP BY  subparts.b_partid
            ) subQGrp2BlackMfgDailyQty,

            (
              SELECT  subparts.b_partid,
                      SUM(punrunhist.qty_bars_processed) totalPcs
              FROM  reco_rstx_calday  calday,
                              -- Good:get_date_toshowin_rpt description
                    reco_rstx_punrun_hist punrunhist,
                    (
                      SELECT DISTINCT
                              subasg.punrun_id,
                              subreq.reqlength,
                              subreq.reqtype,
                              subreq.reqpunch
                              --NOTE: We do not care about PunchSch coating
                              --      because for this report we label all
                              --      punching results as black pieces
                      FROM  reco_rstx_punrun_hist subrun,
                            reco_rstx_punreq_hist subreq,
                            reco_rstx_punasg_hist subasg
                      WHERE   subrun.punrun_id = subasg.punrun_id
                      AND     subasg.punreq_id = subreq.punreq_id
                      AND     subrun.cutsch_hist_id = vn_WorkingHistId
                      AND     subasg.cutsch_hist_id = vn_WorkingHistId
                      AND     subreq.cutsch_hist_id = vn_WorkingHistId
                    ) subQPartData,
                    reco_rstx_tmpshpcalparts subparts
              WHERE   calday.thedate >= vd_FirstDateShown
              AND     calday.thedate < pi_DesiredDay
              AND     calday.calday_id = punrunhist.calday_id
              AND     punrunhist.cutsch_hist_id = vn_WorkingHistId
              AND     punrunhist.punrun_id = subQPartData.punrun_id
              AND     subQPartData.reqlength = subparts.b_partnumlen
              AND     subQPartData.reqtype = subparts.b_parttype
              AND     subQPartData.reqpunch = subparts.b_partpunch
              AND     subparts.sortorder IN (pi_sortOrder, pi_sortOrder2)
              GROUP BY  subparts.b_partid
            ) subQGrp2BlackMfgCummQty    
            
      WHERE   rptGrp1Parts.sortorder = pi_sortOrder
      AND     rptGrp1Parts.n_partid = rptGrp2Parts.n_partid (+)
      AND     rptGrp2Parts.sortorder (+) = pi_sortOrder2
      AND     rptGrp1Parts.n_partid = msibGrp1NoPun.inventory_item_id (+)
      and   msibgrp1nopun.organization_id(+) = 0
      AND     rptGrp1Parts.b_partid = msibGrp1Black.inventory_item_id (+)
      and   msibgrp1black.organization_id(+) = 0
      AND     rptGrp1Parts.g_partid = msibGrp1Galv.inventory_item_id (+)
      and   msibgrp1galv.organization_id(+) = 0
      AND     rptGrp2Parts.b_partid = msibGrp2Black.inventory_item_id (+)
      and   msibgrp2black.organization_id(+) = 0
      AND     rptGrp2Parts.g_partid = msibGrp2Galv.inventory_item_id (+)
      and   msibgrp2galv.organization_id(+) = 0
      AND     rptGrp1Parts.b_partid = subQGrp1BlackShippedQty.b_partid (+)
      AND     rptGrp1Parts.g_partid = subQGrp1GalvShippedQty.g_partid (+)
      AND     rptGrp1Parts.b_partid = subQGrp1BlackMfgDailyQty.b_partid (+)
      AND     rptGrp1Parts.b_partid = subQGrp1BlackMfgCummQty.b_partid (+)
      AND     rptGrp2Parts.b_partid = subQGrp2BlackShippedQty.b_partid (+)
      AND     rptGrp2Parts.g_partid = subQGrp2GalvShippedQty.g_partid (+)
      AND     rptGrp2Parts.b_partid = subQGrp2BlackMfgDailyQty.b_partid (+)
      AND     rptGrp2Parts.b_partid = subQGrp2BlackMfgCummQty.b_partid (+);
    
    vn_CachedSPBMfgTot number;
    vn_CachedDPBMfgTot number;
    vn_CachedSPBMfgTot506 number;
    vn_CachedDPBMfgTot506 number;
    
    --vb_FirstNegativeDateSet BOOLEAN;
  BEGIN
    
   -- vb_FirstNegativeDateSet := false;
  thelocation := 'dailyquery';    
    IF oTheSheetColumnInfo.count > 0
    THEN
      
      nCtrSheetColumnInfo := 1;
      
      LOOP
        
        IF oTheSheetColumnInfo(nCtrSheetColumnInfo).rptColTypeCode
                = 'DAILYPARTINV'
        THEN
          oTheSheetColumnInfo(nCtrSheetColumnInfo).daystrt_npb_tonn := 0;
          oTheSheetColumnInfo(nCtrSheetColumnInfo).daystrt_spb_tonn := 0;
          oTheSheetColumnInfo(nCtrSheetColumnInfo).daystrt_spg_tonn := 0;
          oTheSheetColumnInfo(nCtrSheetColumnInfo).daystrt_dpb_tonn := 0;
          oTheSheetColumnInfo(nCtrSheetColumnInfo).daystrt_dpg_tonn := 0;
          vn_CachedSPBMfgTot := 0;
          vn_CachedDPBMfgTot := 0;
--          vb_FirstNegativeDateSet := false;
          
          FOR rec_TonnagesForRptDate
          IN cur_TonnagesForRptDate(
                  oTheSheetColumnInfo(nCtrSheetColumnInfo).shipment_date, 1, 2)
          LOOP
            oTheSheetColumnInfo(nCtrSheetColumnInfo).daystrt_npb_tonn :=
                oTheSheetColumnInfo(nCtrSheetColumnInfo).daystrt_npb_tonn
                +
                (
                  reco_estimation.convert_to(
                        rec_TonnagesForRptDate.npb_unit_weight,
                        rec_TonnagesForRptDate.npb_weight_uom_code,
                        'TO')
                  *
                  (
                    (
                      rec_TonnagesForRptDate.npb_originvqty - 0 + 0
                    )
                  )
                );
            
            oTheSheetColumnInfo(nCtrSheetColumnInfo).daystrt_spb_tonn :=
                oTheSheetColumnInfo(nCtrSheetColumnInfo).daystrt_spb_tonn
                +
                (
                  reco_estimation.convert_to(
                        rec_TonnagesForRptDate.spb_unit_weight,
                        rec_TonnagesForRptDate.spb_weight_uom_code,
                        'TO')
                  *
                  (
                    (
                      rec_TonnagesForRptDate.spb_originvqty
                      -
                      rec_TonnagesForRptDate.spb_ship_cumm_qty
                    )
                    +
                    rec_TonnagesForRptDate.spb_newpun_cumm_qty
                  )
                );
                           
            oTheSheetColumnInfo(nCtrSheetColumnInfo).daystrt_spg_tonn :=
                oTheSheetColumnInfo(nCtrSheetColumnInfo).daystrt_spg_tonn
                +
                (
                  reco_estimation.convert_to(
                        rec_TonnagesForRptDate.spg_unit_weight,
                        rec_TonnagesForRptDate.spg_weight_uom_code,
                        'TO')
                  *
                  (
                    (
                      rec_TonnagesForRptDate.spg_originvqty
                      -
                      rec_TonnagesForRptDate.spg_ship_cumm_qty
                    )
                    +
                    0
                  )
                );
                
            -- -------------------------------------------------------------------------------------------
--            if ( oTheSheetColumnInfo(nCtrSheetColumnInfo).daystrt_spg_tonn < 0 AND vb_FirstNegativeDateSet = false  )
--              then 
--              oTheSheetColumnInfo(nCtrSheetColumnInfo).vcFirstNegativeDateText := 'TEST';
--              --((to_char(oTheSheetColumnInfo(nCtrSheetColumnInfo).shipment_date,'DY DD-MON')));
--              vb_FirstNegativeDateSet := true;
--            end if;
--                   
--            if ( oTheSheetColumnInfo(nCtrSheetColumnInfo).daystrt_spb_tonn < 0 AND vb_FirstNegativeDateSet = false )
--              then 
--              oTheSheetColumnInfo(nCtrSheetColumnInfo).vcFirstNegativeDateText := 'TEST';
--              --((to_char(oTheSheetColumnInfo(nCtrSheetColumnInfo).shipment_date,'DY DD-MON')));
--              vb_FirstNegativeDateSet := true;
--            end if;              
            -- --------------------------------------------------------------------------------------------
            
            oTheSheetColumnInfo(nCtrSheetColumnInfo).daystrt_dpb_tonn :=
                oTheSheetColumnInfo(nCtrSheetColumnInfo).daystrt_dpb_tonn
                +
                (
                  reco_estimation.convert_to(
                        rec_TonnagesForRptDate.dpb_unit_weight,
                        rec_TonnagesForRptDate.dpb_weight_uom_code,
                        'TO')
                  *
                  (
                    (
                      rec_TonnagesForRptDate.dpb_originvqty
                      -
                      rec_TonnagesForRptDate.dpb_ship_cumm_qty
                    )
                    +
                    rec_TonnagesForRptDate.dpb_newpun_cumm_qty
                  )
                );
            
            oTheSheetColumnInfo(nCtrSheetColumnInfo).daystrt_dpg_tonn :=
                oTheSheetColumnInfo(nCtrSheetColumnInfo).daystrt_dpg_tonn
                +
                (
                  reco_estimation.convert_to(
                        rec_TonnagesForRptDate.dpg_unit_weight,
                        rec_TonnagesForRptDate.dpg_weight_uom_code,
                        'TO')
                  *
                  (
                    (
                      rec_TonnagesForRptDate.dpg_originvqty
                      -
                      rec_TonnagesForRptDate.dpg_ship_cumm_qty
                    )
                    +
                    0
                  )
                );
          END LOOP;
        ELSIF oTheSheetColumnInfo(nCtrSheetColumnInfo).rptColTypeCode
                = 'ENDINVTOTAL'
        THEN
          oTheSheetColumnInfo(nCtrSheetColumnInfo).daystrt_npb_tonn := 0;
          oTheSheetColumnInfo(nCtrSheetColumnInfo).daystrt_spb_tonn := 0;
          oTheSheetColumnInfo(nCtrSheetColumnInfo).daystrt_spg_tonn := 0;
          oTheSheetColumnInfo(nCtrSheetColumnInfo).daystrt_dpb_tonn := 0;
          oTheSheetColumnInfo(nCtrSheetColumnInfo).daystrt_dpg_tonn := 0;
          vn_CachedSPBMfgTot := 0;
          vn_CachedDPBMfgTot := 0;
          
          FOR rec_TonnagesForRptDate
          IN cur_TonnagesForRptDate( (vd_LastDateShown + 1), 1, 2)
          LOOP
            oTheSheetColumnInfo(nCtrSheetColumnInfo).daystrt_npb_tonn :=
                oTheSheetColumnInfo(nCtrSheetColumnInfo).daystrt_npb_tonn
                +
                (
                  reco_estimation.convert_to(
                        rec_TonnagesForRptDate.npb_unit_weight,
                        rec_TonnagesForRptDate.npb_weight_uom_code,
                        'TO')
                  *
                  (
                    (
                      rec_TonnagesForRptDate.npb_originvqty - 0 + 0
                    )
                  )
                );
            
            oTheSheetColumnInfo(nCtrSheetColumnInfo).daystrt_spb_tonn :=
                oTheSheetColumnInfo(nCtrSheetColumnInfo).daystrt_spb_tonn
                +
                (
                  reco_estimation.convert_to(
                        rec_TonnagesForRptDate.spb_unit_weight,
                        rec_TonnagesForRptDate.spb_weight_uom_code,
                        'TO')
                  *
                  (
                    (
                      rec_TonnagesForRptDate.spb_originvqty
                      -
                      rec_TonnagesForRptDate.spb_ship_cumm_qty
                    )
                    +
                    rec_TonnagesForRptDate.spb_newpun_cumm_qty
                  )
                );
            
            oTheSheetColumnInfo(nCtrSheetColumnInfo).daystrt_spg_tonn :=
                oTheSheetColumnInfo(nCtrSheetColumnInfo).daystrt_spg_tonn
                +
                (
                  reco_estimation.convert_to(
                        rec_TonnagesForRptDate.spg_unit_weight,
                        rec_TonnagesForRptDate.spg_weight_uom_code,
                        'TO')
                  *
                  (
                    (
                      rec_TonnagesForRptDate.spg_originvqty
                      -
                      rec_TonnagesForRptDate.spg_ship_cumm_qty
                    )
                    +
                    0
                  )
                );
            
            oTheSheetColumnInfo(nCtrSheetColumnInfo).daystrt_dpb_tonn :=
                oTheSheetColumnInfo(nCtrSheetColumnInfo).daystrt_dpb_tonn
                +
                (
                  reco_estimation.convert_to(
                        rec_TonnagesForRptDate.dpb_unit_weight,
                        rec_TonnagesForRptDate.dpb_weight_uom_code,
                        'TO')
                  *
                  (
                    (
                      rec_TonnagesForRptDate.dpb_originvqty
                      -
                      rec_TonnagesForRptDate.dpb_ship_cumm_qty
                    )
                    +
                    rec_TonnagesForRptDate.dpb_newpun_cumm_qty
                  )
                );
            
            oTheSheetColumnInfo(nCtrSheetColumnInfo).daystrt_dpg_tonn :=
                oTheSheetColumnInfo(nCtrSheetColumnInfo).daystrt_dpg_tonn
                +
                (
                  reco_estimation.convert_to(
                        rec_TonnagesForRptDate.dpg_unit_weight,
                        rec_TonnagesForRptDate.dpg_weight_uom_code,
                        'TO')
                  *
                  (
                    (
                      rec_TonnagesForRptDate.dpg_originvqty
                      -
                      rec_TonnagesForRptDate.dpg_ship_cumm_qty
                    )
                    +
                    0
                  )
                );
            
          END LOOP;
        END IF;

        IF nCtrSheetColumnInfo = oTheSheetColumnInfo.count
        THEN exit;
        END IF;
        
        nCtrSheetColumnInfo := nCtrSheetColumnInfo + 1;
      END LOOP;
    END IF;
      thelocation := 'enddaily';
-- ********************************************************************************** JNL 6.0 START
-- **********************************************************************************
    IF oTheSheetColumnInfo.count > 0
        THEN
          
          nCtrSheetColumnInfo := 1;
          
          LOOP
            
            IF oTheSheetColumnInfo(nCtrSheetColumnInfo).rptColTypeCode
                    = 'DAILYPARTINV'
            THEN
              oTheSheetColumnInfo(nCtrSheetColumnInfo).daystrt506_npb_tonn := 0;
              oTheSheetColumnInfo(nCtrSheetColumnInfo).daystrt506_spb_tonn := 0;
              oTheSheetColumnInfo(nCtrSheetColumnInfo).daystrt506_spg_tonn := 0;
              oTheSheetColumnInfo(nCtrSheetColumnInfo).daystrt506_dpb_tonn := 0;
              oTheSheetColumnInfo(nCtrSheetColumnInfo).daystrt506_dpg_tonn := 0;
              oTheSheetColumnInfo(nCtrSheetColumnInfo).vcFirstNegativeDateText := '';
              vn_CachedSPBMfgTot506 := 0;
              vn_CachedDPBMfgTot506 := 0;
              
              FOR rec_TonnagesForRptDate
              IN cur_TonnagesForRptDate(
                      oTheSheetColumnInfo(nCtrSheetColumnInfo).shipment_date, 3, 4)
              LOOP
                oTheSheetColumnInfo(nCtrSheetColumnInfo).daystrt506_npb_tonn :=
                    oTheSheetColumnInfo(nCtrSheetColumnInfo).daystrt506_npb_tonn
                    +
                    (
                      reco_estimation.convert_to(
                            rec_TonnagesForRptDate.npb_unit_weight,
                            rec_TonnagesForRptDate.npb_weight_uom_code,
                            'TO')
                      *
                      (
                        (
                          NVL(rec_TonnagesForRptDate.npb_originvqty - 0 + 0,0)
                        )
                      )
                    );
                
                oTheSheetColumnInfo(nCtrSheetColumnInfo).daystrt506_spb_tonn :=
                    oTheSheetColumnInfo(nCtrSheetColumnInfo).daystrt506_spb_tonn
                    +
                    (
                      reco_estimation.convert_to(
                            rec_TonnagesForRptDate.spb_unit_weight,
                            rec_TonnagesForRptDate.spb_weight_uom_code,
                            'TO')
                      *
                      (
                        (
                          rec_TonnagesForRptDate.spb_originvqty
                          -
                          rec_TonnagesForRptDate.spb_ship_cumm_qty
                        )
                        +
                        rec_TonnagesForRptDate.spb_newpun_cumm_qty
                      )
                    );
                
                oTheSheetColumnInfo(nCtrSheetColumnInfo).daystrt506_spg_tonn :=
                    oTheSheetColumnInfo(nCtrSheetColumnInfo).daystrt506_spg_tonn
                    +
                    (
                      reco_estimation.convert_to(
                            rec_TonnagesForRptDate.spg_unit_weight,
                            rec_TonnagesForRptDate.spg_weight_uom_code,
                            'TO')
                      *
                      (
                        (
                          rec_TonnagesForRptDate.spg_originvqty
                          -
                          rec_TonnagesForRptDate.spg_ship_cumm_qty
                        )
                        +
                        0
                      )
                    );
                
                oTheSheetColumnInfo(nCtrSheetColumnInfo).daystrt506_dpb_tonn :=
                    oTheSheetColumnInfo(nCtrSheetColumnInfo).daystrt506_dpb_tonn
                    +
                    (
                      reco_estimation.convert_to(
                            rec_TonnagesForRptDate.dpb_unit_weight,
                            rec_TonnagesForRptDate.dpb_weight_uom_code,
                            'TO')
                      *
                      (
                        (
                          rec_TonnagesForRptDate.dpb_originvqty
                          -
                          rec_TonnagesForRptDate.dpb_ship_cumm_qty
                        )
                        +
                        rec_TonnagesForRptDate.dpb_newpun_cumm_qty
                      )
                    );
                
                oTheSheetColumnInfo(nCtrSheetColumnInfo).daystrt506_dpg_tonn :=
                    oTheSheetColumnInfo(nCtrSheetColumnInfo).daystrt506_dpg_tonn
                    +
                    (
                      reco_estimation.convert_to(
                            rec_TonnagesForRptDate.dpg_unit_weight,
                            rec_TonnagesForRptDate.dpg_weight_uom_code,
                            'TO')
                      *
                      (
                        (
                          rec_TonnagesForRptDate.dpg_originvqty
                          -
                          rec_TonnagesForRptDate.dpg_ship_cumm_qty
                        )
                        +
                        0
                      )
                    );
              END LOOP;
            ELSIF oTheSheetColumnInfo(nCtrSheetColumnInfo).rptColTypeCode
                    = 'ENDINVTOTAL'
            THEN
              oTheSheetColumnInfo(nCtrSheetColumnInfo).daystrt506_npb_tonn := 0;
              oTheSheetColumnInfo(nCtrSheetColumnInfo).daystrt506_spb_tonn := 0;
              oTheSheetColumnInfo(nCtrSheetColumnInfo).daystrt506_spg_tonn := 0;
              oTheSheetColumnInfo(nCtrSheetColumnInfo).daystrt506_dpb_tonn := 0;
              oTheSheetColumnInfo(nCtrSheetColumnInfo).daystrt506_dpg_tonn := 0;
              vn_CachedSPBMfgTot506 := 0;
              vn_CachedDPBMfgTot506 := 0;
              
              FOR rec_TonnagesForRptDate
              IN cur_TonnagesForRptDate( (vd_LastDateShown + 1), 3, 4)
              LOOP
                oTheSheetColumnInfo(nCtrSheetColumnInfo).daystrt506_npb_tonn :=
                    oTheSheetColumnInfo(nCtrSheetColumnInfo).daystrt506_npb_tonn
                    +
                    (
                      reco_estimation.convert_to(
                            rec_TonnagesForRptDate.npb_unit_weight,
                            rec_TonnagesForRptDate.npb_weight_uom_code,
                            'TO')
                      *
                      (
                        (
                          rec_TonnagesForRptDate.npb_originvqty - 0 + 0
                        )
                      )
                    );
                
                oTheSheetColumnInfo(nCtrSheetColumnInfo).daystrt506_spb_tonn :=
                    oTheSheetColumnInfo(nCtrSheetColumnInfo).daystrt506_spb_tonn
                    +
                    (
                      reco_estimation.convert_to(
                            rec_TonnagesForRptDate.spb_unit_weight,
                            rec_TonnagesForRptDate.spb_weight_uom_code,
                            'TO')
                      *
                      (
                        (
                          rec_TonnagesForRptDate.spb_originvqty
                          -
                          rec_TonnagesForRptDate.spb_ship_cumm_qty
                        )
                        +
                        rec_TonnagesForRptDate.spb_newpun_cumm_qty
                      )
                    );
                
                oTheSheetColumnInfo(nCtrSheetColumnInfo).daystrt506_spg_tonn :=
                    oTheSheetColumnInfo(nCtrSheetColumnInfo).daystrt506_spg_tonn
                    +
                    (
                      reco_estimation.convert_to(
                            rec_TonnagesForRptDate.spg_unit_weight,
                            rec_TonnagesForRptDate.spg_weight_uom_code,
                            'TO')
                      *
                      (
                        (
                          rec_TonnagesForRptDate.spg_originvqty
                          -
                          rec_TonnagesForRptDate.spg_ship_cumm_qty
                        )
                        +
                        0
                      )
                    );
                
                oTheSheetColumnInfo(nCtrSheetColumnInfo).daystrt506_dpb_tonn :=
                    oTheSheetColumnInfo(nCtrSheetColumnInfo).daystrt506_dpb_tonn
                    +
                    (
                      reco_estimation.convert_to(
                            rec_TonnagesForRptDate.dpb_unit_weight,
                            rec_TonnagesForRptDate.dpb_weight_uom_code,
                            'TO')
                      *
                      (
                        (
                          rec_TonnagesForRptDate.dpb_originvqty
                          -
                          rec_TonnagesForRptDate.dpb_ship_cumm_qty
                        )
                        +
                        rec_TonnagesForRptDate.dpb_newpun_cumm_qty
                      )
                    );
                
                oTheSheetColumnInfo(nCtrSheetColumnInfo).daystrt506_dpg_tonn :=
                    oTheSheetColumnInfo(nCtrSheetColumnInfo).daystrt506_dpg_tonn
                    +
                    (
                      reco_estimation.convert_to(
                            rec_TonnagesForRptDate.dpg_unit_weight,
                            rec_TonnagesForRptDate.dpg_weight_uom_code,
                            'TO')
                      *
                      (
                        (
                          rec_TonnagesForRptDate.dpg_originvqty
                          -
                          rec_TonnagesForRptDate.dpg_ship_cumm_qty
                        )
                        +
                        0
                      )
                    );
              END LOOP;
            END IF;
            
            IF nCtrSheetColumnInfo = oTheSheetColumnInfo.count
            THEN exit;
            END IF;
            
            nCtrSheetColumnInfo := nCtrSheetColumnInfo + 1;
          END LOOP;
        END IF;
          thelocation := 'enddaily2';
-- **********************************************************************************
-- ********************************************************************************** JNL 6.0 END
  END;
  
  ---
  -- Prepare spreadsheet
  ---

  reco_web_functions.reset_sheet;
  thelocation := 'reset';
  reco_web_functions.table_attr := 'border="1" frame="border" rules="all"';
  thelocation := 'attr';
--  reco_web_functions.open_spreadsheet;  --('Shipping_Calendar');  
  IF NOT bSummaryReport THEN
  	reco_web_functions.open_spreadsheet('NODATE:reco_steel_shipments_report'); --Added by RS on 03/04/2026.
  ELSE
  	reco_web_functions.open_spreadsheet('NODATE:reco_steel_shipments_summary_report'); --Added by RS on 03/04/2026.
  END IF;
  thelocation := 'open';
  ---
  -- Print notification if we couldn't actually access start-of-day info
  ---
  
  IF vc_WorkingHistUser != 'NIGHTLY AUTO REFRESH'
  THEN
    reco_web_functions.clear_headers;
    reco_web_functions.col_span := 16;
    reco_web_functions.cell_attr := '';
    reco_web_functions.add_header_column(
      'Warning: Could not access Morning INV numbers. '||
      'The shipping is accurate, but the displayed inventory numbers '||
      'may not match the Morning INV quantities');
    reco_web_functions.print_header;
  END IF;
  
  ---
  -- Header - Print First Row - Date
  ---
  thelocation := 'clear';
  reco_web_functions.clear_headers;
  
  reco_web_functions.col_span := oTheSheetColumnInfo(1).num_child_cols;
  --reco_web_functions.col_span := oTheSheetColumnInfoSP(1).num_child_cols;
  --reco_web_functions.col_span := oTheSheetColumnInfoDP(1).num_child_cols;
  reco_web_functions.cell_attr := '';
  reco_web_functions.add_header_column('Steel Ship');
  thelocation := 'begin sheet';  
   
    DECLARE
        vn_TmpDayCtr number;
         TYPE nt_type IS TABLE OF number;
         nt nt_type := nt_type (2 ,(oTheSheetColumnInfo.count - 1) , (oTheSheetColumnInfo.count - 2));
    BEGIN
        vn_TmpDayCtr := 1;
        
        reco_web_functions.col_span := 0;
        
        IF NOT bSummaryReport THEN
          FOR colctr IN 2 .. (oTheSheetColumnInfo.count - 1)
          LOOP
            reco_web_functions.col_span :=
                reco_web_functions.col_span
                  + oTheSheetColumnInfo(colctr).num_child_cols;
            
            IF oTheSheetColumnInfo(colctr).shipment_date
                    != oTheSheetColumnInfo(colctr+1).shipment_date
            OR oTheSheetColumnInfo(colctr+1).shipment_date IS NULL
            THEN
              reco_web_functions.cell_attr := vc_Color_OddDayNorm;
              IF MOD(vn_TmpDayCtr,2) = 0
              THEN reco_web_functions.cell_attr := vc_Color_EvenDayNorm;
              END IF;
              
              reco_web_functions.add_header_column(
                TO_CHAR(oTheSheetColumnInfo(colctr).shipment_date,'DY DD-MON'));
              
              vn_TmpDayCtr := vn_TmpDayCtr + 1;
              
              reco_web_functions.col_span := 0;
            END IF;
          END LOOP;
        
        ELSIF bSummaryReport THEN
          -- JNL REPORTING CONDITION START
          FOR colctr IN 1..nt.count
          LOOP
            reco_web_functions.col_span :=
                reco_web_functions.col_span
                  + oTheSheetColumnInfo(colctr).num_child_cols;
            
            IF oTheSheetColumnInfo(colctr).shipment_date
                    != oTheSheetColumnInfo(colctr+1).shipment_date
            OR oTheSheetColumnInfo(colctr+1).shipment_date IS NULL
            THEN
              reco_web_functions.cell_attr := vc_Color_OddDayNorm;
              IF MOD(vn_TmpDayCtr,2) = 0
              THEN reco_web_functions.cell_attr := vc_Color_EvenDayNorm;
              END IF;
              
              reco_web_functions.add_header_column(
                TO_CHAR(oTheSheetColumnInfo(colctr).shipment_date,'DY DD-MON'));
              
              vn_TmpDayCtr := vn_TmpDayCtr + 1;
              
              reco_web_functions.col_span := 0;
            END IF;
          END LOOP;
          -- JNL REPORTING CONDITION END
          
        END IF;
        
      END;
  
  reco_web_functions.col_span :=
          oTheSheetColumnInfo(oTheSheetColumnInfo.count).num_child_cols;
  reco_web_functions.cell_attr := '';
  reco_web_functions.add_header_column(' ');
  
  reco_web_functions.print_header;
   thelocation := 'header';
  ---
  -- Header - Print each date shipment name and inventory header / etc
  ---
  
  reco_web_functions.clear_headers;
  
  DECLARE
    vn_TmpDayCtr number;
    vc_TmpTxtToPrint varchar2(1000);
    TYPE nt_type IS TABLE OF number;
    nt nt_type := nt_type (2 ,(oTheSheetColumnInfo.count - 1) , (oTheSheetColumnInfo.count - 2));

  BEGIN
    vn_TmpDayCtr := 0;
    
    IF NOT bSummaryReport THEN
  thelocation := 'docount';      
      FOR colctr IN 1 .. oTheSheetColumnInfo.count
      LOOP
        reco_web_functions.col_span :=
            oTheSheetColumnInfo(colctr).num_child_cols;
        
        IF oTheSheetColumnInfo(colctr).rptColTypeCode = 'PARTNAME'
        THEN
          reco_web_functions.cell_attr := '';
          vc_TmpTxtToPrint :=
              TO_CHAR(SYSDATE,'YYYY')||'<br>'||TO_CHAR(SYSDATE,'DD-MON');
                      
        ELSIF oTheSheetColumnInfo(colctr).rptColTypeCode = 'DAILYPARTINV'
        THEN
          reco_web_functions.cell_attr := vc_Color_InvText;
          vc_TmpTxtToPrint := 'Morning<br>INV';
  
        ELSIF oTheSheetColumnInfo(colctr).rptColTypeCode = 'DELIVEREDSHIP'
        THEN
          reco_web_functions.cell_attr := '';
          vc_TmpTxtToPrint :=
              '<A HREF="http://ebs.vincic-sf.grpsc.net:8000/pls/RECO/reco_web_info.display_shipment?p_shipment_id='||
              TO_CHAR(oTheSheetColumnInfo(colctr).shipment_id)||
              '" target="new">'||
              SUBSTR(oTheSheetColumnInfo(colctr).tracking_number,1,
                INSTR(oTheSheetColumnInfo(colctr).tracking_number,'-',1,3))||
              '<br>'||
              SUBSTR(oTheSheetColumnInfo(colctr).tracking_number,
                INSTR(oTheSheetColumnInfo(colctr).tracking_number,'-',1,3) + 1)||
              '-'||
              oTheSheetColumnInfo(colctr).shipment_status||
              '</A>';
        ELSIF oTheSheetColumnInfo(colctr).rptColTypeCode = 'PENDINGSHIP'
        THEN
          reco_web_functions.cell_attr := '';
          vc_TmpTxtToPrint :=
              '<A HREF="http://ebs.vincic-sf.grpsc.net:8000/pls/RECO/reco_web_info.display_shipment?p_shipment_id='||
              TO_CHAR(oTheSheetColumnInfo(colctr).shipment_id)||
              '" target="new">'||
              SUBSTR(oTheSheetColumnInfo(colctr).tracking_number,1,
                INSTR(oTheSheetColumnInfo(colctr).tracking_number,'-',1,3))||
              '<br>'||
              SUBSTR(oTheSheetColumnInfo(colctr).tracking_number,
                INSTR(oTheSheetColumnInfo(colctr).tracking_number,'-',1,3) + 1)||
              '-'||
              oTheSheetColumnInfo(colctr).STATE||
              '</A>';
        ELSIF oTheSheetColumnInfo(colctr).rptColTypeCode = 'DAYPARTPROPOSEDMFG'
        THEN
          reco_web_functions.cell_attr := vc_Color_InvText;
          vc_TmpTxtToPrint := 'Steel<br>Manuf';
          
        ELSIF oTheSheetColumnInfo(colctr).rptColTypeCode = 'ENDINVTOTAL'
        THEN
          reco_web_functions.cell_attr := vc_Color_InvText;
          vc_TmpTxtToPrint := 'Ending<br>INV';
          
        ELSIF oTheSheetColumnInfo(colctr).rptColTypeCode = 'NEGATIVEINV'
        THEN
          reco_web_functions.cell_attr := vc_Color_InvText;
          vc_TmpTxtToPrint := 'INV <br>Negative on';
          
        END IF;
        
        reco_web_functions.add_header_column(vc_TmpTxtToPrint);
        
        vn_TmpDayCtr := vn_TmpDayCtr + 1;
      END LOOP;
      
    ELSIF bSummaryReport THEN
    
      -- JNL REPORTING CONDITION START
        FOR colctr IN 1 .. oTheSheetColumnInfo.count
        LOOP
          reco_web_functions.col_span :=
              oTheSheetColumnInfo(colctr).num_child_cols;
          
          IF oTheSheetColumnInfo(colctr).rptColTypeCode = 'PARTNAME'
          THEN
            reco_web_functions.cell_attr := '';
            vc_TmpTxtToPrint :=
                TO_CHAR(SYSDATE,'YYYY')||'<br>'||TO_CHAR(SYSDATE,'DD-MON');
                        
          ELSIF oTheSheetColumnInfo(colctr).rptColTypeCode = 'DAILYPARTINV'
          THEN
            reco_web_functions.cell_attr := vc_Color_InvText;
            vc_TmpTxtToPrint := 'Morning<br>INV';
            
          ELSIF oTheSheetColumnInfo(colctr).rptColTypeCode = 'ENDINVTOTAL'
          THEN
            reco_web_functions.cell_attr := vc_Color_InvText;
            vc_TmpTxtToPrint := 'Ending<br>INV';
            
          ELSIF oTheSheetColumnInfo(colctr).rptColTypeCode = 'NEGATIVEINV'
          THEN
            reco_web_functions.cell_attr := vc_Color_InvText;
            vc_TmpTxtToPrint := 'INV <br>Negative on';
            
          END IF;
          
          --JNL REPORT IF CONDITION
        IF colctr = 1 OR colctr = 2 OR colctr = (oTheSheetColumnInfo.count ) OR colctr = (oTheSheetColumnInfo.count - 1) THEN
           reco_web_functions.add_header_column(vc_TmpTxtToPrint);
        END IF;
          
          vn_TmpDayCtr := vn_TmpDayCtr + 1;
        END LOOP;
       -- JNL REPORTING CONDITION END
    END IF;
    
  END;
   thelocation := 'header2';
  reco_web_functions.print_header;
  
  ---
  -- Header - Print B / G items
  ---
  
  reco_web_functions.clear_headers;
  
  DECLARE
    vn_TmpDayCtr number;
    vc_TmpTxtToPrint varchar2(1000);
    
    TYPE nt_type IS TABLE OF number;
	  nt nt_type := nt_type (2 ,(oTheSheetColumnInfo.count - 1) , (oTheSheetColumnInfo.count - 2));
    
    -- ************************************************************************************************ JNL START TOTWGHT
    PROCEDURE proc_PrintTotalWght
    IS
    BEGIN -- proc_PrintTotalWght
    
        IF NOT bSummaryReport THEN
          FOR colctr IN 1 .. oTheSheetColumnInfo.count
          LOOP
            
            IF oTheSheetColumnInfo(colctr).rptColTypeCode = 'PARTNAME'
            THEN
              reco_web_functions.col_span := 1;
              reco_web_functions.cell_attr := vc_Color_DelivStdTxt;
              reco_web_functions.add_data_column('ShipTot');                      
            
            ELSIF oTheSheetColumnInfo(colctr).rptColTypeCode = 'DAILYPARTINV'
            THEN
                reco_web_functions.col_span := 2;
                IF colctr = 2
                THEN reco_web_functions.col_span := 3;
                END IF;
                reco_web_functions.cell_attr := vc_Color_DelivStdTxt;
                reco_web_functions.add_data_column(' ');                            -- JNL END
            ELSIF oTheSheetColumnInfo(colctr).rptColTypeCode = 'DELIVEREDSHIP'
            THEN
              reco_web_functions.col_span := 2;
              reco_web_functions.cell_attr := vc_Color_DelivStdTxt;
                reco_web_functions.add_data_column(
                  TO_CHAR(ROUND(oTheSheetColumnInfo(colctr).ship_totwgt,2),
                          '9999.00')||' Tons');
  
            ELSIF oTheSheetColumnInfo(colctr).rptColTypeCode = 'PENDINGSHIP'
            THEN
              reco_web_functions.col_span := 2;
              reco_web_functions.cell_attr := vc_Color_DelivStdTxt;
  
                reco_web_functions.add_data_column(
                  TO_CHAR(ROUND(oTheSheetColumnInfo(colctr).ship_totwgt,2),
                          '9999.00')||' Tons');
  --          elsif oTheSheetColumnInfo(colctr).rptColTypeCode = 'DAYPARTPROPOSEDMFG'
  --          then
  -- 
  --              reco_web_functions.col_span := 1;
  --              reco_web_functions.cell_attr := vc_Color_DelivStdTxt;
  --              reco_web_functions.add_data_column(' ');                          -- JNL END
  
            ELSIF oTheSheetColumnInfo(colctr).rptColTypeCode = 'ENDINVTOTAL'
            THEN
                reco_web_functions.col_span := 2;
                reco_web_functions.cell_attr := vc_Color_DelivStdTxt;
                reco_web_functions.add_data_column(' ');                      
           
           ELSIF oTheSheetColumnInfo(colctr).rptColTypeCode = 'NEGATIVEINV'
            THEN
                reco_web_functions.col_span := 2;
                reco_web_functions.cell_attr := vc_Color_DelivStdTxt;
                reco_web_functions.add_data_column(' ');  
           
            END IF;
          END LOOP;
        
        -- JNL REPORTING CONDITION START
        ELSIF bSummaryReport THEN
          FOR colctr IN 1 .. oTheSheetColumnInfo.count
          LOOP
            
            IF oTheSheetColumnInfo(colctr).rptColTypeCode = 'PARTNAME'
            THEN
              reco_web_functions.col_span := 1;
              reco_web_functions.cell_attr := vc_Color_DelivStdTxt;
              --JNL REPORT IF CONDITION
              IF colctr = 1 OR colctr = 2 OR colctr = (oTheSheetColumnInfo.count ) OR colctr = (oTheSheetColumnInfo.count - 1) THEN
                reco_web_functions.add_data_column('ShipTot');                      
              END IF;
              
            ELSIF oTheSheetColumnInfo(colctr).rptColTypeCode = 'DAILYPARTINV'
            THEN
                reco_web_functions.col_span := 2;
                IF colctr = 2
                THEN reco_web_functions.col_span := 3;
                END IF;
                reco_web_functions.cell_attr := vc_Color_DelivStdTxt;
                
                --JNL REPORT IF CONDITION
                IF colctr = 1 OR colctr = 2 OR colctr = (oTheSheetColumnInfo.count ) OR colctr = (oTheSheetColumnInfo.count - 1) THEN
                 reco_web_functions.add_data_column(' ');                            -- JNL END
                END IF;
                
            ELSIF oTheSheetColumnInfo(colctr).rptColTypeCode = 'DELIVEREDSHIP'
            THEN
              reco_web_functions.col_span := 2;
              reco_web_functions.cell_attr := vc_Color_DelivStdTxt;
              
              --JNL REPORT IF CONDITION
              IF colctr = 1 OR colctr = 2 OR colctr = (oTheSheetColumnInfo.count ) OR colctr = (oTheSheetColumnInfo.count - 1) THEN
                reco_web_functions.add_data_column(
                  TO_CHAR(ROUND(oTheSheetColumnInfo(colctr).ship_totwgt,2),
                          '9999.00')||' Tons');
              END IF;
  
            ELSIF oTheSheetColumnInfo(colctr).rptColTypeCode = 'PENDINGSHIP'
            THEN
              reco_web_functions.col_span := 2;
              reco_web_functions.cell_attr := vc_Color_DelivStdTxt;
  
            --JNL REPORT IF CONDITION
              IF colctr = 1 OR colctr = 2 OR colctr = (oTheSheetColumnInfo.count ) OR colctr = (oTheSheetColumnInfo.count - 1) THEN
                
                reco_web_functions.add_data_column(
                  TO_CHAR(ROUND(oTheSheetColumnInfo(colctr).ship_totwgt,2),
                          '9999.00')||' Tons');
              END IF;
              
  --          elsif oTheSheetColumnInfo(colctr).rptColTypeCode = 'DAYPARTPROPOSEDMFG'
  --          then
  -- 
  --              reco_web_functions.col_span := 1;
  --              reco_web_functions.cell_attr := vc_Color_DelivStdTxt;
  --              reco_web_functions.add_data_column(' ');                          -- JNL END
  
            ELSIF oTheSheetColumnInfo(colctr).rptColTypeCode = 'ENDINVTOTAL'
            THEN
                reco_web_functions.col_span := 2;
                reco_web_functions.cell_attr := vc_Color_DelivStdTxt;
                
              --JNL REPORT IF CONDITION
              IF colctr = 1 OR colctr = 2 OR colctr = (oTheSheetColumnInfo.count ) OR colctr = (oTheSheetColumnInfo.count - 1) THEN
                reco_web_functions.add_data_column(' ');                      
              END IF;
              
           ELSIF oTheSheetColumnInfo(colctr).rptColTypeCode = 'NEGATIVEINV'
            THEN
                reco_web_functions.col_span := 2;
                reco_web_functions.cell_attr := vc_Color_DelivStdTxt;
                
                --JNL REPORT IF CONDITION
                IF colctr = 1 OR colctr = 2 OR colctr = (oTheSheetColumnInfo.count ) OR colctr = (oTheSheetColumnInfo.count - 1) THEN
                  reco_web_functions.add_data_column(' '); 
                END IF;
           
            END IF;
          END LOOP;
        END IF;
        -- JNL REPORTING CONDITION END
        
        reco_web_functions.print_datarow;
    END; -- proc_PrintTotalWght
-- ************************************************************************************************ JNL END TOTWGHT 

  BEGIN
    vn_TmpDayCtr := 0;
    proc_PrintTotalWght;                         -- JNL TOTAL Weight 8.0
      thelocation := 'sheetsummary';
    IF NOT bSummaryReport THEN
      FOR colctr IN 1 .. oTheSheetColumnInfo.count
      LOOP
        
        IF oTheSheetColumnInfo(colctr).rptColTypeCode = 'PARTNAME'
        THEN
          reco_web_functions.col_span := 1;
          reco_web_functions.cell_attr := vc_Color_InvText;
          vc_TmpTxtToPrint := '<b>Parts</b>';
          reco_web_functions.add_header_column(vc_TmpTxtToPrint);
        ELSIF oTheSheetColumnInfo(colctr).rptColTypeCode = 'DAILYPARTINV'
        THEN
          IF oTheSheetColumnInfo(colctr).num_child_cols = 3
          THEN
            reco_web_functions.col_span := 1;
            reco_web_functions.cell_attr := '';
            vc_TmpTxtToPrint := '<b>N</b>';
            reco_web_functions.add_header_column(vc_TmpTxtToPrint);
          END IF;
          reco_web_functions.col_span := 1;
          reco_web_functions.cell_attr := '';
          vc_TmpTxtToPrint := '<b>B</b>';
          reco_web_functions.add_header_column(vc_TmpTxtToPrint);
          reco_web_functions.col_span := 1;
          reco_web_functions.cell_attr := '';
          vc_TmpTxtToPrint := '<b>G</b>';
          reco_web_functions.add_header_column(vc_TmpTxtToPrint);
  --      elsif oTheSheetColumnInfo(colctr).rptColTypeCode = 'ENDINVTOTAL'
  --      then
  --        reco_web_functions.col_span := 1;
  --        reco_web_functions.cell_attr := '';
  --        vc_TmpTxtToPrint := '<b>B</b>';
  --        reco_web_functions.add_header_column(vc_TmpTxtToPrint);
  --        reco_web_functions.col_span := 1;
  --        reco_web_functions.cell_attr := '';
  --        vc_TmpTxtToPrint := '<b>G</b>';
  --        reco_web_functions.add_header_column(vc_TmpTxtToPrint);
        ELSIF oTheSheetColumnInfo(colctr).rptColTypeCode = 'DELIVEREDSHIP'
        THEN
          reco_web_functions.col_span := 1;
          reco_web_functions.cell_attr := '';
          vc_TmpTxtToPrint := '<b>B</b>';
          reco_web_functions.add_header_column(vc_TmpTxtToPrint);
          reco_web_functions.col_span := 1;
          reco_web_functions.cell_attr := '';
          vc_TmpTxtToPrint := '<b>G</b>';
          reco_web_functions.add_header_column(vc_TmpTxtToPrint);
        ELSIF oTheSheetColumnInfo(colctr).rptColTypeCode = 'PENDINGSHIP'
        THEN
          reco_web_functions.col_span := 1;
          reco_web_functions.cell_attr := '';
          vc_TmpTxtToPrint := '<b>B</b>';
          reco_web_functions.add_header_column(vc_TmpTxtToPrint);
          reco_web_functions.col_span := 1;
          reco_web_functions.cell_attr := '';
          vc_TmpTxtToPrint := '<b>G</b>';
          reco_web_functions.add_header_column(vc_TmpTxtToPrint);
        ELSIF oTheSheetColumnInfo(colctr).rptColTypeCode = 'DAYPARTPROPOSEDMFG'
        THEN
          reco_web_functions.col_span := 1;
          reco_web_functions.cell_attr := '';
          vc_TmpTxtToPrint := '<b>B</b>';
          reco_web_functions.add_header_column(vc_TmpTxtToPrint);
        ELSIF oTheSheetColumnInfo(colctr).rptColTypeCode = 'ENDINVTOTAL'
        THEN
          reco_web_functions.col_span := 1;
          reco_web_functions.cell_attr := '';
          vc_TmpTxtToPrint := '<b>B</b>';
          reco_web_functions.add_header_column(vc_TmpTxtToPrint);
          reco_web_functions.col_span := 1;
          reco_web_functions.cell_attr := '';
          vc_TmpTxtToPrint := '<b>G</b>';
          reco_web_functions.add_header_column(vc_TmpTxtToPrint);
        ELSIF oTheSheetColumnInfo(colctr).rptColTypeCode = 'NEGATIVEINV'
        THEN
          reco_web_functions.col_span := 1;
          reco_web_functions.cell_attr := '';
          vc_TmpTxtToPrint := ' ';
          reco_web_functions.add_header_column(vc_TmpTxtToPrint);
          reco_web_functions.col_span := 1;
          reco_web_functions.cell_attr := '';
          vc_TmpTxtToPrint := ' ';
          reco_web_functions.add_header_column(vc_TmpTxtToPrint);
        END IF;
        
        vn_TmpDayCtr := vn_TmpDayCtr + 1;
      END LOOP;
      
    -- JNL REPORTING CONDITION START 
    ELSIF bSummaryReport THEN    
      FOR colctr IN 1 .. oTheSheetColumnInfo.count
      LOOP
        
        IF oTheSheetColumnInfo(colctr).rptColTypeCode = 'PARTNAME'
        THEN
          reco_web_functions.col_span := 1;
          reco_web_functions.cell_attr := vc_Color_InvText;
          vc_TmpTxtToPrint := '<b>Parts</b>';
          reco_web_functions.add_header_column(vc_TmpTxtToPrint);
        ELSIF oTheSheetColumnInfo(colctr).rptColTypeCode = 'DAILYPARTINV'
        THEN
          IF oTheSheetColumnInfo(colctr).num_child_cols = 3
          THEN
            reco_web_functions.col_span := 1;
            reco_web_functions.cell_attr := '';
            vc_TmpTxtToPrint := '<b>N</b>';
            reco_web_functions.add_header_column(vc_TmpTxtToPrint);
          END IF;
          reco_web_functions.col_span := 1;
          reco_web_functions.cell_attr := '';
          vc_TmpTxtToPrint := '<b>B</b>';
          
          --JNL REPORT IF CONDITION
          IF colctr = 1 OR colctr = 2 OR colctr = (oTheSheetColumnInfo.count ) OR colctr = (oTheSheetColumnInfo.count - 1) THEN
            reco_web_functions.add_header_column(vc_TmpTxtToPrint);
          END IF;
          
          reco_web_functions.col_span := 1;
          reco_web_functions.cell_attr := '';
          vc_TmpTxtToPrint := '<b>G</b>';
          
          --JNL REPORT IF CONDITION
          IF colctr = 1 OR colctr = 2 OR colctr = (oTheSheetColumnInfo.count ) OR colctr = (oTheSheetColumnInfo.count - 1) THEN
            reco_web_functions.add_header_column(vc_TmpTxtToPrint);
          END IF;
          
  --      elsif oTheSheetColumnInfo(colctr).rptColTypeCode = 'ENDINVTOTAL'
  --      then
  --        reco_web_functions.col_span := 1;
  --        reco_web_functions.cell_attr := '';
  --        vc_TmpTxtToPrint := '<b>B</b>';
  --        reco_web_functions.add_header_column(vc_TmpTxtToPrint);
  --        reco_web_functions.col_span := 1;
  --        reco_web_functions.cell_attr := '';
  --        vc_TmpTxtToPrint := '<b>G</b>';
  --        reco_web_functions.add_header_column(vc_TmpTxtToPrint);
  
        -- JNL COMMENTED THE BELOW SECTION - REPORTING - 6/13/2017
  --      elsif oTheSheetColumnInfo(colctr).rptColTypeCode = 'DELIVEREDSHIP'
  --      then
  --        reco_web_functions.col_span := 1;
  --        reco_web_functions.cell_attr := '';
  --        vc_TmpTxtToPrint := '<b>B</b>';
  --        reco_web_functions.add_header_column(vc_TmpTxtToPrint);
  --        reco_web_functions.col_span := 1;
  --        reco_web_functions.cell_attr := '';
  --        vc_TmpTxtToPrint := '<b>G</b>';
  --        
  --        --JNL REPORT IF CONDITION
  --        if colctr = 1 OR colctr = 2 OR colctr = (oTheSheetColumnInfo.count ) OR colctr = (oTheSheetColumnInfo.count - 1) then
  --          reco_web_functions.add_header_column(vc_TmpTxtToPrint);
  --        end if;  
  --        
  --      elsif oTheSheetColumnInfo(colctr).rptColTypeCode = 'PENDINGSHIP'
  --      then
  --        reco_web_functions.col_span := 1;
  --        reco_web_functions.cell_attr := '';
  --        vc_TmpTxtToPrint := '<b>B</b>';
  --        reco_web_functions.add_header_column(vc_TmpTxtToPrint);
  --        reco_web_functions.col_span := 1;
  --        reco_web_functions.cell_attr := '';
  --        vc_TmpTxtToPrint := '<b>G</b>';
  --        
  --         --JNL REPORT IF CONDITION
  --        if colctr = 1 OR colctr = 2 OR colctr = (oTheSheetColumnInfo.count ) OR colctr = (oTheSheetColumnInfo.count - 1) then
  --          reco_web_functions.add_header_column(vc_TmpTxtToPrint);
  --        end if;
  --        
  --      elsif oTheSheetColumnInfo(colctr).rptColTypeCode = 'DAYPARTPROPOSEDMFG'
  --      then
  --        reco_web_functions.col_span := 1;
  --        reco_web_functions.cell_attr := '';
  --        vc_TmpTxtToPrint := '<b>B</b>';
  --        
  --         --JNL REPORT IF CONDITION
  --        if colctr = 1 OR colctr = 2 OR colctr = (oTheSheetColumnInfo.count ) OR colctr = (oTheSheetColumnInfo.count - 1) then
  --          reco_web_functions.add_header_column(vc_TmpTxtToPrint);
  --        end if;
        
        ELSIF oTheSheetColumnInfo(colctr).rptColTypeCode = 'ENDINVTOTAL'
        THEN
          reco_web_functions.col_span := 1;
          reco_web_functions.cell_attr := '';
          vc_TmpTxtToPrint := '<b>B</b>';
          
          --JNL REPORT IF CONDITION
          IF colctr = 1 OR colctr = 2 OR colctr = (oTheSheetColumnInfo.count ) OR colctr = (oTheSheetColumnInfo.count - 1) THEN
           reco_web_functions.add_header_column(vc_TmpTxtToPrint);
          END IF;
          
          reco_web_functions.col_span := 1;
          reco_web_functions.cell_attr := '';
          
          --JNL REPORT IF CONDITION
          IF colctr = 1 OR colctr = 2 OR colctr = (oTheSheetColumnInfo.count ) OR colctr = (oTheSheetColumnInfo.count - 1) THEN
            vc_TmpTxtToPrint := '<b>G</b>';
          END IF;
          
          reco_web_functions.add_header_column(vc_TmpTxtToPrint);
        ELSIF oTheSheetColumnInfo(colctr).rptColTypeCode = 'NEGATIVEINV'
        THEN
          reco_web_functions.col_span := 1;
          reco_web_functions.cell_attr := '';
          vc_TmpTxtToPrint := ' ';
          reco_web_functions.add_header_column(vc_TmpTxtToPrint);
          reco_web_functions.col_span := 1;
          reco_web_functions.cell_attr := '';
          vc_TmpTxtToPrint := ' ';
          
           --JNL REPORT IF CONDITION
          IF colctr = 1 OR colctr = 2 OR colctr = (oTheSheetColumnInfo.count ) OR colctr = (oTheSheetColumnInfo.count - 1) THEN
            reco_web_functions.add_header_column(vc_TmpTxtToPrint);
          END IF;
          
        END IF;
        
        vn_TmpDayCtr := vn_TmpDayCtr + 1;
      END LOOP;
      
    END IF;
    -- JNL REPORTING CONDITION END
    
  END;
  
  reco_web_functions.print_header;
  
  ---
  -- If there are no parts / rows, then we can exit early
  -- (and also prevent possible errors of partqty = 0)
  ---
    thelocation := 'parts2';
  DECLARE
    vn_TotalPartRows number;
  BEGIN
    SELECT COUNT(*) INTO vn_TotalPartRows FROM reco_rstx_tmpshpcalparts;

    IF vn_TotalPartRows = 0
    THEN
      reco_web_functions.clear_headers;
      
      reco_web_functions.col_span := 9;
      reco_web_functions.cell_attr := '';
      reco_web_functions.add_header_column(
        'Steel Shipments');
      reco_web_functions.print_header;
      
      reco_web_functions.clear_headers;
      reco_web_functions.col_span := 9;
      reco_web_functions.cell_attr := '';
      reco_web_functions.add_header_column(
        'There are no pending Shipments or Parts that are shown');
      reco_web_functions.print_header;
      
      reco_web_functions.clear_headers;
      reco_web_functions.col_span := 9;
      reco_web_functions.cell_attr := '';
      reco_web_functions.add_header_column(
        'for parameter dates '||TO_CHAR(vd_FirstDateShown,'DD-MON-YYYY')||
        ' to '||TO_CHAR(vd_LastDateShown,'DD-MON-YYYY')||', so report is blank');
      reco_web_functions.print_header;
      reco_web_Functions.close_spreadsheet;
      RETURN;
    END IF;
  END;
  
  ---
  -- Body - Print part rows
  ---
  
  DECLARE
    vb_PrevPartRowExists BOOLEAN;
    vr_PrevPartRow reco_rstx_tmpshpcalparts%ROWTYPE;
    
    vn_TmpNPInvQty number;
    vn_TmpBPInvQty number;
    vn_TmpGPInvQty number;
    
    vn_TmpDayCtr number;
       
    CURSOR cur_ThisPartVals(pi_GivenBlackId IN number,
                            pi_GivenGalvId IN number)
    IS
      SELECT  rs.truck_date shipment_date,
              NVL(rs.tracking_number,rst.stop_identifier) tracking_number,
              rst.shipment_id,
              CASE
              WHEN rs.truck_status = 'D'
              THEN 1
              ELSE 2
              END sortord_shipstat,
              rs.truck_status shipment_status,
              SUM(NVL(rspblack.quantity,0)) totblack,
              SUM(NVL(rspgalv.quantity,0)) totgalv
      FROM  reco_truck rs, reco_truckstop rst,
            reco_shipment_parts_v rspblack,
            reco_shipment_parts_v rspgalv
      WHERE   rst.shipment_id = rspblack.shipment_id (+)
      AND     rspblack.part_id (+) = pi_GivenBlackId
      AND     rspblack.orig_subinventory_code (+) = 'RSTX'
      AND     rst.shipment_id = rspgalv.shipment_id (+)
      AND     rspgalv.part_id (+) = pi_GivenGalvId
      AND     rspgalv.orig_subinventory_code (+) = 'RSTX'
      AND     rs.truck_status IN ('A','H','B','D')
      AND     rs.truck_date >= vd_FirstDateShown
      AND     rs.truck_date <= vd_LastDateShown
      AND     rst.stop_truck_id = rs.truck_id
      GROUP BY  rs.truck_date,
                NVL(rs.tracking_number,rst.stop_identifier),
                rst.shipment_id,
                CASE
                WHEN rs.truck_status = 'D'
                THEN 1
                ELSE 2
                END,
                rs.truck_status
      HAVING      SUM(NVL(rspblack.quantity,0)) > 0
      OR          SUM(NVL(rspgalv.quantity,0)) > 0
      ORDER BY  rs.truck_date,
                CASE
                WHEN rs.truck_status = 'D'
                THEN 1
                ELSE 2
                END,
                NVL(rs.tracking_number,rst.stop_identifier),
                rst.shipment_id;
    
    TYPE coll_ThisPartVals IS TABLE OF cur_ThisPartVals%ROWTYPE;
    oThisPartVals coll_ThisPartVals; -- Fetched, so don't initialize
    nCtrPartVals number;




-- ************************************************************************************************* -- JNL 6.0    
    PROCEDURE proc_PrintTwoWeightsRowsSP( p_partType IN VARCHAR2)
    IS
      v_partType VARCHAR2(20);
    BEGIN -- proc_PrintTwoWeightsRowsSP
      
      v_partType := p_partType;
      
      FOR rowctr IN 1 .. 1
      LOOP
       
       IF NOT bSummaryReport THEN
          FOR colctr IN 1 .. oTheSheetColumnInfo.count
          LOOP
            
            IF oTheSheetColumnInfo(colctr).rptColTypeCode = 'PARTNAME'
            THEN
              reco_web_functions.col_span := 1;
              reco_web_functions.cell_attr := '';
              IF rowctr = 1
              THEN reco_web_functions.add_data_column('StlTons');
              END IF;
  
            ELSIF oTheSheetColumnInfo(colctr).rptColTypeCode = 'DAILYPARTINV'
            THEN
              IF rowctr = 1
              THEN
                IF colctr = 2
                THEN
                  reco_web_functions.col_span := 1;
                  reco_web_functions.cell_attr := '';
                  
                  IF v_partType LIKE ('S504%') THEN                         
                    reco_web_functions.add_data_column(           
                      TO_CHAR(
                        ROUND(oTheSheetColumnInfo(colctr).daystrt_npb_tonn,2),
                        '9999.00')||'T');
                  ELSIF v_partType LIKE ('D504%') THEN
                    reco_web_functions.add_data_column(' ');
                    
                  ELSIF v_partType LIKE ('S506%') THEN
                    reco_web_functions.add_data_column(           
                      TO_CHAR(
                        ROUND(oTheSheetColumnInfo(colctr).daystrt506_npb_tonn,2),
                        '9999.00')||'T');
                  ELSIF v_partType LIKE ('D506%') THEN
                    reco_web_functions.add_data_column(' ');
                  END IF;
                  
                END IF;
                
                reco_web_functions.col_span := 1;                                
                reco_web_functions.cell_attr := '';
                
                 IF v_partType LIKE ('S504%') THEN                         
                    reco_web_functions.add_data_column(
                      TO_CHAR(
                        ROUND(oTheSheetColumnInfo(colctr).daystrt_spb_tonn,2),
                        '9999.00')||'T');
                 ELSIF v_partType LIKE ('D504%') THEN
                     reco_web_functions.add_data_column(           
                       TO_CHAR(
                         ROUND(oTheSheetColumnInfo(colctr).daystrt_dpb_tonn,2),
                         '9999.00')||'T');
                  ELSIF v_partType LIKE ('S506%') THEN
                    reco_web_functions.add_data_column(           
                      TO_CHAR(
                        ROUND(oTheSheetColumnInfo(colctr).daystrt506_spb_tonn,2),
                        '9999.00')||'T');
                  ELSIF v_partType LIKE ('D506%') THEN
                    reco_web_functions.add_data_column(           
                      TO_CHAR(
                        ROUND(oTheSheetColumnInfo(colctr).daystrt506_dpb_tonn,2),
                        '9999.00')||'T');
                  END IF;
                
                reco_web_functions.col_span := 1;                                  
                reco_web_functions.cell_attr := '';
                IF v_partType LIKE ('S504%') THEN                         
                    reco_web_functions.add_data_column(
                      TO_CHAR(
                        ROUND(oTheSheetColumnInfo(colctr).daystrt_spg_tonn,2),
                        '9999.00')||'T');
                  ELSIF v_partType LIKE ('D504%') THEN
                    reco_web_functions.add_data_column(           
                      TO_CHAR(
                        ROUND(oTheSheetColumnInfo(colctr).daystrt_dpg_tonn,2),
                        '9999.00')||'T');
                  ELSIF v_partType LIKE ('S506%') THEN
                    reco_web_functions.add_data_column(           
                      TO_CHAR(
                        ROUND(oTheSheetColumnInfo(colctr).daystrt506_spg_tonn,2),
                        '9999.00')||'T');
                  ELSIF v_partType LIKE ('D506%') THEN
                    reco_web_functions.add_data_column(           
                      TO_CHAR(
                        ROUND(oTheSheetColumnInfo(colctr).daystrt506_dpg_tonn,2),
                        '9999.00')||'T');
                  END IF;
             
              ELSIF rowctr = 2                                                      
              THEN
                reco_web_functions.col_span := 2;
                IF colctr = 2
                THEN reco_web_functions.col_span := 3;
                END IF;
                reco_web_functions.cell_attr := '';
                reco_web_functions.add_data_column(' ');                           
              END IF;                                                               
  
            ELSIF oTheSheetColumnInfo(colctr).rptColTypeCode = 'DELIVEREDSHIP'
            THEN
              reco_web_functions.col_span := 2;
              reco_web_functions.cell_attr := '';
              IF rowctr = 1
              THEN
                reco_web_functions.add_data_column(
                  TO_CHAR(ROUND(WeightForPartType(oTheSheetColumnInfo(colctr).shipment_id, v_partType),2),         --oTheSheetColumnInfoSP(colctr).ship_stlwgt,2),
                          '9999.00')||' Tons');
              END IF;
            ELSIF oTheSheetColumnInfo(colctr).rptColTypeCode = 'PENDINGSHIP'
            THEN
              reco_web_functions.col_span := 2;
              reco_web_functions.cell_attr := '';
              IF rowctr = 1
              THEN
                reco_web_functions.add_data_column(
                  TO_CHAR(ROUND(WeightForPartType(oTheSheetColumnInfo(colctr).shipment_id, v_partType),2),         --oTheSheetColumnInfo(colctr).ship_stlwgt,2),
                          '9999.00')||' Tons');
              END IF; 
            
            ELSIF oTheSheetColumnInfo(colctr).rptColTypeCode = 'ENDINVTOTAL'
            THEN
              IF rowctr = 1
              THEN
                reco_web_functions.col_span := 1;
                reco_web_functions.cell_attr := '';
                IF v_partType LIKE ('S504%') THEN                         
                    reco_web_functions.add_data_column(
                      TO_CHAR(
                        ROUND(oTheSheetColumnInfo(colctr).daystrt_spb_tonn,2),
                        '9999.00')||'T');
                  ELSIF v_partType LIKE ('D504%') THEN
                    reco_web_functions.add_data_column(           
                      TO_CHAR(
                        ROUND(oTheSheetColumnInfo(colctr).daystrt_dpb_tonn,2),
                        '9999.00')||'T');
                  ELSIF v_partType LIKE ('S506%') THEN
                    reco_web_functions.add_data_column(           
                      TO_CHAR(
                        ROUND(oTheSheetColumnInfo(colctr).daystrt506_spb_tonn,2),
                        '9999.00')||'T');
                  ELSIF v_partType LIKE ('D506%') THEN
                    reco_web_functions.add_data_column(           
                      TO_CHAR(
                        ROUND(oTheSheetColumnInfo(colctr).daystrt506_dpb_tonn,2),
                        '9999.00')||'T');
                END IF;
                
                reco_web_functions.col_span := 1;
                reco_web_functions.cell_attr := '';
                
                IF v_partType LIKE ('S504%') THEN                         -- JNL NEW WRITE UP
                    reco_web_functions.add_data_column(
                      TO_CHAR(
                        ROUND(oTheSheetColumnInfo(colctr).daystrt_spg_tonn,2),
                        '9999.00')||'T');
                  ELSIF v_partType LIKE ('D504%') THEN
                    reco_web_functions.add_data_column(           
                      TO_CHAR(
                        ROUND(oTheSheetColumnInfo(colctr).daystrt_dpg_tonn,2),
                        '9999.00')||'T');
                  ELSIF v_partType LIKE ('S506%') THEN
                    reco_web_functions.add_data_column(           
                      TO_CHAR(
                        ROUND(oTheSheetColumnInfo(colctr).daystrt506_spg_tonn,2),
                        '9999.00')||'T');
                  ELSIF v_partType LIKE ('D506%') THEN
                    reco_web_functions.add_data_column(           
                      TO_CHAR(
                        ROUND(oTheSheetColumnInfo(colctr).daystrt506_dpg_tonn,2),
                        '9999.00')||'T');
                END IF;
                  
              ELSIF rowctr = 2                                                -- JNL START
              THEN
                reco_web_functions.col_span := 1;
                reco_web_functions.cell_attr := '';
                reco_web_functions.add_data_column(' ');                      -- JNL END
              END IF;
              
              ELSIF oTheSheetColumnInfo(colctr).rptColTypeCode = 'NEGATIVEINV'
              THEN
                reco_web_functions.col_span := 2;
                reco_web_functions.cell_attr := '';
                IF rowctr = 1
                THEN
                  reco_web_functions.add_data_column(' ');
                ELSIF rowctr = 2                                                -- JNL START
                THEN
                  reco_web_functions.col_span := 2;
                  reco_web_functions.cell_attr := '';
                  reco_web_functions.add_data_column(' ');                      -- JNL END
              END IF;
              
            END IF;
          END LOOP;
        
        ELSIF bSummaryReport THEN
          -- JNL REPORTING CONDITION START
          FOR colctr IN 1 .. oTheSheetColumnInfo.count
          LOOP
            
            IF oTheSheetColumnInfo(colctr).rptColTypeCode = 'PARTNAME' AND
               (colctr = 1 OR colctr = 2 OR colctr = (oTheSheetColumnInfo.count ) OR colctr = (oTheSheetColumnInfo.count - 1))
            THEN
              reco_web_functions.col_span := 1;
              reco_web_functions.cell_attr := '';
              IF rowctr = 1 
              THEN reco_web_functions.add_data_column('StlTons');
              END IF;
  
            ELSIF oTheSheetColumnInfo(colctr).rptColTypeCode = 'DAILYPARTINV' AND
               (colctr = 1 OR colctr = 2 OR colctr = (oTheSheetColumnInfo.count ) OR colctr = (oTheSheetColumnInfo.count - 1))
            THEN
              IF rowctr = 1
              THEN
                IF colctr = 2 
                THEN
                  reco_web_functions.col_span := 1;
                  reco_web_functions.cell_attr := '';
                  
                  IF v_partType LIKE ('S504%')  THEN                         
                    
                    reco_web_functions.add_data_column(           
                      TO_CHAR(
                        ROUND(oTheSheetColumnInfo(colctr).daystrt_npb_tonn,2),
                        '9999.00')||'T');
                  ELSIF v_partType LIKE ('D504%') THEN
                    
                    reco_web_functions.add_data_column(' ');
                    
                  ELSIF v_partType LIKE ('S506%') THEN
                    
                    reco_web_functions.add_data_column(           
                      TO_CHAR(
                        ROUND(oTheSheetColumnInfo(colctr).daystrt506_npb_tonn,2),
                        '9999.00')||'T');
                        
                  ELSIF v_partType LIKE ('D506%') THEN
                    reco_web_functions.add_data_column(' ');
                  END IF;
                  
                END IF;
                
                reco_web_functions.col_span := 1;                                
                reco_web_functions.cell_attr := '';
                
                 IF v_partType LIKE ('S504%') THEN                         
                    
                    reco_web_functions.add_data_column(
                      TO_CHAR(
                        ROUND(oTheSheetColumnInfo(colctr).daystrt_spb_tonn,2),
                        '9999.00')||'T');
                        
                 ELSIF v_partType LIKE ('D504%')THEN
                     reco_web_functions.add_data_column(           
                       TO_CHAR(
                         ROUND(oTheSheetColumnInfo(colctr).daystrt_dpb_tonn,2),
                         '9999.00')||'T');
                  ELSIF v_partType LIKE ('S506%') THEN
                    reco_web_functions.add_data_column(           
                      TO_CHAR(
                        ROUND(oTheSheetColumnInfo(colctr).daystrt506_spb_tonn,2),
                        '9999.00')||'T');
                  ELSIF v_partType LIKE ('D506%') THEN
                    reco_web_functions.add_data_column(           
                      TO_CHAR(
                        ROUND(oTheSheetColumnInfo(colctr).daystrt506_dpb_tonn,2),
                        '9999.00')||'T');
                  END IF;
                
                reco_web_functions.col_span := 1;                                  
                reco_web_functions.cell_attr := '';
                IF v_partType LIKE ('S504%') THEN                         
                    reco_web_functions.add_data_column(
                      TO_CHAR(
                        ROUND(oTheSheetColumnInfo(colctr).daystrt_spg_tonn,2),
                        '9999.00')||'T');
                  ELSIF v_partType LIKE ('D504%') THEN
                    reco_web_functions.add_data_column(           
                      TO_CHAR(
                        ROUND(oTheSheetColumnInfo(colctr).daystrt_dpg_tonn,2),
                        '9999.00')||'T');
                  ELSIF v_partType LIKE ('S506%') THEN
                    reco_web_functions.add_data_column(           
                      TO_CHAR(
                        ROUND(oTheSheetColumnInfo(colctr).daystrt506_spg_tonn,2),
                        '9999.00')||'T');
                  ELSIF v_partType LIKE ('D506%') THEN
                    reco_web_functions.add_data_column(           
                      TO_CHAR(
                        ROUND(oTheSheetColumnInfo(colctr).daystrt506_dpg_tonn,2),
                        '9999.00')||'T');
                  END IF;
             
              ELSIF rowctr = 2                                                      
              THEN
                reco_web_functions.col_span := 2;
                IF colctr = 2
                THEN reco_web_functions.col_span := 3;
                END IF;
                reco_web_functions.cell_attr := '';
                reco_web_functions.add_data_column(' ');                           
              END IF;                                                               
            
            ELSIF oTheSheetColumnInfo(colctr).rptColTypeCode = 'ENDINVTOTAL' AND
               (colctr = 1 OR colctr = 2 OR colctr = (oTheSheetColumnInfo.count ) OR colctr = (oTheSheetColumnInfo.count - 1))
            THEN
              IF rowctr = 1
              THEN
                reco_web_functions.col_span := 1;
                reco_web_functions.cell_attr := '';
                IF v_partType LIKE ('S504%') THEN                         
                    reco_web_functions.add_data_column(
                      TO_CHAR(
                        ROUND(oTheSheetColumnInfo(colctr).daystrt_spb_tonn,2),
                        '9999.00')||'T');
                  ELSIF v_partType LIKE ('D504%') THEN
                    reco_web_functions.add_data_column(           
                      TO_CHAR(
                        ROUND(oTheSheetColumnInfo(colctr).daystrt_dpb_tonn,2),
                        '9999.00')||'T');
                  ELSIF v_partType LIKE ('S506%') THEN
                    reco_web_functions.add_data_column(           
                      TO_CHAR(
                        ROUND(oTheSheetColumnInfo(colctr).daystrt506_spb_tonn,2),
                        '9999.00')||'T');
                  ELSIF v_partType LIKE ('D506%') THEN
                    reco_web_functions.add_data_column(           
                      TO_CHAR(
                        ROUND(oTheSheetColumnInfo(colctr).daystrt506_dpb_tonn,2),
                        '9999.00')||'T');
                END IF;
                
                reco_web_functions.col_span := 1;
                reco_web_functions.cell_attr := '';
                
                IF v_partType LIKE ('S504%') THEN                         -- JNL NEW WRITE UP
                    reco_web_functions.add_data_column(
                      TO_CHAR(
                        ROUND(oTheSheetColumnInfo(colctr).daystrt_spg_tonn,2),
                        '9999.00')||'T');
                  ELSIF v_partType LIKE ('D504%') THEN
                    reco_web_functions.add_data_column(           
                      TO_CHAR(
                        ROUND(oTheSheetColumnInfo(colctr).daystrt_dpg_tonn,2),
                        '9999.00')||'T');
                  ELSIF v_partType LIKE ('S506%') THEN
                    reco_web_functions.add_data_column(           
                      TO_CHAR(
                        ROUND(oTheSheetColumnInfo(colctr).daystrt506_spg_tonn,2),
                        '9999.00')||'T');
                  ELSIF v_partType LIKE ('D506%') THEN
                    reco_web_functions.add_data_column(           
                      TO_CHAR(
                        ROUND(oTheSheetColumnInfo(colctr).daystrt506_dpg_tonn,2),
                        '9999.00')||'T');
                END IF;
                  
              ELSIF rowctr = 2                                           -- JNL START
              THEN
                reco_web_functions.col_span := 1;
                reco_web_functions.cell_attr := '';
                reco_web_functions.add_data_column(' ');                      -- JNL END
              END IF;
              
              ELSIF oTheSheetColumnInfo(colctr).rptColTypeCode = 'NEGATIVEINV' AND
               (colctr = 1 OR colctr = 2 OR colctr = (oTheSheetColumnInfo.count ) OR colctr = (oTheSheetColumnInfo.count - 1))
              THEN
                reco_web_functions.col_span := 2;
                reco_web_functions.cell_attr := '';
                IF rowctr = 1 
                THEN
                  reco_web_functions.add_data_column(' ');
                ELSIF rowctr = 2                                                -- JNL START
                THEN
                  reco_web_functions.col_span := 2;
                  reco_web_functions.cell_attr := '';
                  reco_web_functions.add_data_column(' ');                      -- JNL END
              END IF;
              
            END IF;
          END LOOP;
        
        END IF;
        -- JNL REPORTING CONDITION END
        
        reco_web_functions.print_datarow;
      END LOOP;
    END; -- proc_PrintTwoWeightsRowsSP
-- ------------------------------------------------------------------------------------------------------------------------------
-- ------------------------------------------------------------------------------------------------------------------------------
FUNCTION getFirstNegativeDateText(
         sectionorder IN number, 
         pi_partName IN VARCHAR2)
RETURN VARCHAR2
IS
    vc_FirstNegativeDateText VARCHAR2(100);
    vb_FirstNegativeDateSet BOOLEAN;
    vc_PartName VARCHAR2(100);
BEGIN
    vb_FirstNegativeDateSet := FALSE;
    vc_PartName := '';
    
    FOR rec_CurrPartRow  IN
    (
      SELECT *
      FROM reco_rstx_tmpshpcalparts 
      WHERE 
           n_PartNumLen BETWEEN 4 AND 34        -- JNL 4.0
           --and sortorder = sectionorder
           AND reco_rstx_tmpshpcalparts.G_PARTNAME = pi_partName
      ORDER BY  sortorder,          -- 1=S504 parts, 2=D504 parts, 3=s506, 4=d506, 5=AllOther parts
                g_partpunch,
                g_parttype,
                g_partnumlen
    )
    LOOP
          
      vb_FirstNegativeDateSet := FALSE;
      vc_PartName := rec_CurrPartRow.G_PARTNAME;
      vn_TmpNPInvQty := rec_CurrPartRow.n_originvqty;
      vn_TmpBPInvQty := rec_CurrPartRow.b_originvqty;
      vn_TmpGPInvQty := rec_CurrPartRow.g_originvqty;
            
      OPEN cur_ThisPartVals(rec_CurrPartRow.b_partid,
                            rec_CurrPartRow.g_partid);
      FETCH cur_ThisPartVals BULK COLLECT INTO oThisPartVals;
      CLOSE cur_ThisPartVals;
      
      nCtrPartVals := 1;
      
      FOR colctr IN 1 .. oTheSheetColumnInfo.count
      LOOP     
      
        IF oTheSheetColumnInfo(colctr).rptColTypeCode = 'DAILYPARTINV'
        THEN
      
            IF ( vn_TmpGPInvQty < 0 AND vb_FirstNegativeDateSet = FALSE  )
              THEN vc_FirstNegativeDateText := ((TO_CHAR(oTheSheetColumnInfo(colctr).shipment_date,'DY DD-MON')));
                   vb_FirstNegativeDateSet := TRUE;
                  EXIT;
            END IF;
                   
            IF ( vn_TmpBPInvQty < 0 AND vb_FirstNegativeDateSet = FALSE )
                THEN vc_FirstNegativeDateText := ((TO_CHAR(oTheSheetColumnInfo(colctr).shipment_date,'DY DD-MON')));
                     vb_FirstNegativeDateSet := TRUE;
                EXIT;
            END IF; 
            
        ELSIF oTheSheetColumnInfo(colctr).rptColTypeCode = 'DELIVEREDSHIP'
        THEN
          IF nCtrPartVals <= oThisPartVals.count
          AND oThisPartVals(nCtrPartVals).shipment_id =
                oTheSheetColumnInfo(colctr).shipment_id
          THEN
          
              -- ---------------------------------------------------------------------------------------------------------
              -- ---------------------------------------------------------------------------------------------------------
              IF ( oThisPartVals(nCtrPartVals).totgalv < 0 AND vb_FirstNegativeDateSet = FALSE  )
              THEN vc_FirstNegativeDateText := ((TO_CHAR(oTheSheetColumnInfo(colctr).shipment_date,'DY DD-MON')));
                   vb_FirstNegativeDateSet := TRUE;
                  EXIT;
              END IF;
                     
              IF ( oThisPartVals(nCtrPartVals).totblack < 0 AND vb_FirstNegativeDateSet = FALSE )
                  THEN vc_FirstNegativeDateText := ((TO_CHAR(oTheSheetColumnInfo(colctr).shipment_date,'DY DD-MON')));
                       vb_FirstNegativeDateSet := TRUE;
                  EXIT;
              END IF; 
              -- ---------------------------------------------------------------------------------------------------------
              -- ---------------------------------------------------------------------------------------------------------
              
              nCtrPartVals := nCtrPartVals + 1;

          END IF;
        ELSIF oTheSheetColumnInfo(colctr).rptColTypeCode = 'PENDINGSHIP'
        THEN
          IF nCtrPartVals <= oThisPartVals.count
          AND oThisPartVals(nCtrPartVals).shipment_id =
                oTheSheetColumnInfo(colctr).shipment_id
          THEN
            IF oThisPartVals(nCtrPartVals).totblack != 0
            THEN
              vn_TmpBPInvQty := vn_TmpBPInvQty - oThisPartVals(nCtrPartVals).totblack;
            END IF;
            
            IF oThisPartVals(nCtrPartVals).totgalv != 0
            THEN
              vn_TmpGPInvQty := vn_TmpGPInvQty - oThisPartVals(nCtrPartVals).totgalv;
            END IF;
            
            nCtrPartVals := nCtrPartVals + 1;
            
            -- ---------------------------------------------------------------------------------------------------------
            -- ---------------------------------------------------------------------------------------------------------
            IF ( vn_TmpGPInvQty < 0 AND vb_FirstNegativeDateSet = FALSE  )
              THEN vc_FirstNegativeDateText := ((TO_CHAR(oTheSheetColumnInfo(colctr).shipment_date,'DY DD-MON')));
                   vb_FirstNegativeDateSet := TRUE;
                  EXIT;
            END IF;
                   
            IF ( vn_TmpBPInvQty < 0 AND vb_FirstNegativeDateSet = FALSE )
                THEN vc_FirstNegativeDateText := ((TO_CHAR(oTheSheetColumnInfo(colctr).shipment_date,'DY DD-MON')));
                     vb_FirstNegativeDateSet := TRUE;
                EXIT;
            END IF;
            -- ---------------------------------------------------------------------------------------------------------
            -- ---------------------------------------------------------------------------------------------------------

          END IF;
            
        END IF;
      END LOOP;
thelocation := 'partrow';
--      vr_PrevPartRow := rec_CurrPartRow;
    
    END LOOP; 
    
RETURN vc_FirstNegativeDateText;   
EXCEPTION
WHEN OTHERS THEN
   raise_application_error(-20001,'An error was encountered - '||thelocation||':'||SQLCODE||' -ERROR- '||SQLERRM);
END;
-- -------------------------------------------------------------------------------------------------------------------------------- ------------------------------------------------------------------------------------------------------------------------------
-- ------------------------------------------------------------------------------------------------------------------------------
FUNCTION getEndInvNumber(
         sectionorder IN number, 
         pi_partName IN VARCHAR2,
         pi_partType IN VARCHAR2)
RETURN NUMBER
IS
    vc_TotalEndInvNumber NUMBER;
    vb_FirstNegativeDateSet BOOLEAN;
    vc_PartName VARCHAR2(100);
BEGIN
    vc_TotalEndInvNumber := 0;
    vc_PartName := ' ';
    
    FOR rec_CurrPartRow  IN
    (
      SELECT *
      FROM reco_rstx_tmpshpcalparts 
      WHERE 
           n_PartNumLen BETWEEN 4 AND 34        -- JNL 4.0
           AND sortorder = sectionorder
           AND reco_rstx_tmpshpcalparts.G_PARTNAME = pi_partName
      ORDER BY  sortorder,          -- 1=S504 parts, 2=D504 parts, 3=s506, 4=d506, 5=AllOther parts
                g_partpunch,
                g_parttype,
                g_partnumlen
    )
    LOOP
          
      vc_PartName := rec_CurrPartRow.G_PARTNAME;
      vn_TmpNPInvQty := rec_CurrPartRow.n_originvqty;
      vn_TmpBPInvQty := rec_CurrPartRow.b_originvqty;
      vn_TmpGPInvQty := rec_CurrPartRow.g_originvqty;
      
      OPEN cur_ThisPartVals(rec_CurrPartRow.b_partid,
                            rec_CurrPartRow.g_partid);
      FETCH cur_ThisPartVals BULK COLLECT INTO oThisPartVals;
      CLOSE cur_ThisPartVals;
      
      nCtrPartVals := 1;
      
--      for colctr in 1 .. oTheSheetColumnInfo.count
--      loop     
--      
----        if oTheSheetColumnInfo(colctr).rptColTypeCode = 'DAILYPARTINV'
----        then
----            if ( vn_TmpGPInvQty < 0 AND vb_FirstNegativeDateSet = false  )
----              then vc_FirstNegativeDateText := ((to_char(oTheSheetColumnInfo(colctr).shipment_date,'DY DD-MON')));
----                   vb_FirstNegativeDateSet := true;
----                  EXIT;
----            end if;
----                   
----            if ( vn_TmpBPInvQty < 0 AND vb_FirstNegativeDateSet = false )
----                then vc_FirstNegativeDateText := ((to_char(oTheSheetColumnInfo(colctr).shipment_date,'DY DD-MON')));
----                     vb_FirstNegativeDateSet := true;
----                EXIT;
----            end if;    
----            
----        end if;
--      end loop;

--      vr_PrevPartRow := rec_CurrPartRow;
    
    END LOOP; 
    
RETURN vc_TotalEndInvNumber;   
EXCEPTION
WHEN OTHERS THEN
   raise_application_error(-20001,'An error was encountered - '||SQLCODE||' -ERROR- '||SQLERRM);
END;
-- ------------------------------------------------------------------------------------------------------------------------------
-- ------------------------------------------------------------------------------------------------------------------------------

PROCEDURE printsection( sectionorder IN number ) 
IS
    vc_PartName VARCHAR2(100);
BEGIN
    vb_PrevPartRowExists := FALSE;
    vc_PartName := ' ';
    
    FOR rec_CurrPartRow  IN
    (
      SELECT *
      FROM reco_rstx_tmpshpcalparts 
      WHERE 
           n_PartNumLen BETWEEN 4 AND 34        -- JNL 4.0
           AND sortorder = sectionorder
      ORDER BY  sortorder,          -- 1=S504 parts, 2=D504 parts, 3=s506, 4=d506, 5=AllOther parts
                g_partpunch,
                g_parttype,
                g_partnumlen
    )
    LOOP
    
      vc_PartName := rec_CurrPartRow.G_PARTNAME;
      vn_TmpNPInvQty := rec_CurrPartRow.n_originvqty;
      vn_TmpBPInvQty := rec_CurrPartRow.b_originvqty;
      vn_TmpGPInvQty := rec_CurrPartRow.g_originvqty;
      
      OPEN cur_ThisPartVals(rec_CurrPartRow.b_partid,
                            rec_CurrPartRow.g_partid);
      FETCH cur_ThisPartVals BULK COLLECT INTO oThisPartVals;
      CLOSE cur_ThisPartVals;
      
      nCtrPartVals := 1;
      
      vn_TmpDayCtr := 0;
      
      IF NOT bSummaryReport THEN
        FOR colctr IN 1 .. oTheSheetColumnInfo.count
        LOOP

          IF oTheSheetColumnInfo(colctr).rptColTypeCode = 'PARTNAME'
          THEN
            IF rec_CurrPartRow.sortorder = sectionorder
            THEN
              reco_web_functions.col_span := 1;
              reco_web_functions.cell_attr := vc_Color_InvText;
              reco_web_functions.add_data_column(rec_CurrPartRow.G_PARTNAME);  -- JNL
            ELSE
              reco_web_functions.col_span := 1;
              reco_web_functions.cell_attr := '';
              reco_web_functions.add_data_column(
                rec_CurrPartRow.g_partname);
            END IF;
                              
          ELSIF oTheSheetColumnInfo(colctr).rptColTypeCode = 'DAILYPARTINV'
          THEN
            vn_TmpDayCtr := vn_TmpDayCtr + 1;
            
            IF oTheSheetColumnInfo(colctr).num_child_cols = 3
            THEN
              reco_web_functions.col_span := 1;
              reco_web_functions.cell_attr := vc_Color_OddDayNorm;
              IF MOD(vn_TmpDayCtr,2) = 0
              THEN reco_web_functions.cell_attr := vc_Color_EvenDayNorm;
              END IF;
              IF vn_TmpNPInvQty < 0
                THEN reco_web_functions.cell_attr := vc_Color_Negative;
              END IF;
              reco_web_functions.add_data_column(TO_CHAR(vn_TmpNPInvQty));
            END IF;
            
            reco_web_functions.col_span := 1;
            reco_web_functions.cell_attr := vc_Color_OddDayNorm;
            IF MOD(vn_TmpDayCtr,2) = 0
              THEN reco_web_functions.cell_attr := vc_Color_EvenDayNorm;
            END IF;
            IF vn_TmpBPInvQty < 0
              THEN reco_web_functions.cell_attr := vc_Color_Negative;
            END IF;
            reco_web_functions.add_data_column(TO_CHAR(vn_TmpBPInvQty));
            
            reco_web_functions.col_span := 1;
            reco_web_functions.cell_attr := vc_Color_OddDayNorm;
            IF MOD(vn_TmpDayCtr,2) = 0
              THEN reco_web_functions.cell_attr := vc_Color_EvenDayNorm;
            END IF;
            
            IF vn_TmpGPInvQty < 0
              THEN reco_web_functions.cell_attr := vc_Color_Negative;
            END IF;
            reco_web_functions.add_data_column(TO_CHAR(vn_TmpGPInvQty));
                 
          ELSIF oTheSheetColumnInfo(colctr).rptColTypeCode = 'DELIVEREDSHIP'
          THEN
            IF nCtrPartVals <= oThisPartVals.count
            AND oThisPartVals(nCtrPartVals).shipment_id =
                  oTheSheetColumnInfo(colctr).shipment_id
            THEN
              IF oThisPartVals(nCtrPartVals).totblack = 0
              THEN
                reco_web_functions.col_span := 1;
                reco_web_functions.cell_attr := vc_Color_DelivStdTxt;
                reco_web_functions.add_data_column(' ');
              ELSIF oThisPartVals(nCtrPartVals).totblack != 0
              THEN
                reco_web_functions.col_span := 1;
                reco_web_functions.cell_attr := vc_Color_BlackSteel;
                reco_web_functions.add_data_column(
                  TO_CHAR(oThisPartVals(nCtrPartVals).totblack));
  --              vn_TmpBPInvQty := vn_TmpBPInvQty -
  --                oThisPartVals(nCtrPartVals).totblack;
              END IF;
              
              IF oThisPartVals(nCtrPartVals).totgalv = 0
              THEN
                reco_web_functions.col_span := 1;
                reco_web_functions.cell_attr := vc_Color_DelivStdTxt;
                reco_web_functions.add_data_column(' ');
              ELSIF oThisPartVals(nCtrPartVals).totgalv != 0
              THEN
                reco_web_functions.col_span := 1;
                reco_web_functions.cell_attr := vc_Color_DelivStdTxt;
                reco_web_functions.add_data_column(
                  TO_CHAR(oThisPartVals(nCtrPartVals).totgalv));
  --              vn_TmpGPInvQty := vn_TmpGPInvQty -
  --                oThisPartVals(nCtrPartVals).totgalv;
              END IF;
              
              nCtrPartVals := nCtrPartVals + 1;
            ELSE
              reco_web_functions.col_span := 1;
              reco_web_functions.cell_attr := vc_Color_DelivStdTxt;
              reco_web_functions.add_data_column(' ');
              reco_web_functions.add_data_column(' ');
            END IF;
          ELSIF oTheSheetColumnInfo(colctr).rptColTypeCode = 'PENDINGSHIP'
          THEN
            IF nCtrPartVals <= oThisPartVals.count
            AND oThisPartVals(nCtrPartVals).shipment_id =
                  oTheSheetColumnInfo(colctr).shipment_id
            THEN
              IF oThisPartVals(nCtrPartVals).totblack = 0
              THEN
                reco_web_functions.col_span := 1;
                reco_web_functions.cell_attr := vc_Color_OddDayNorm;
                IF MOD(vn_TmpDayCtr,2) = 0
                THEN reco_web_functions.cell_attr := vc_Color_EvenDayNorm;
                END IF;
                reco_web_functions.add_data_column(' ');
              ELSIF oThisPartVals(nCtrPartVals).totblack != 0
              THEN
                reco_web_functions.col_span := 1;
                reco_web_functions.cell_attr := vc_Color_BlackSteel;
                reco_web_functions.add_data_column(
                  TO_CHAR(oThisPartVals(nCtrPartVals).totblack));
                vn_TmpBPInvQty := vn_TmpBPInvQty -
                  oThisPartVals(nCtrPartVals).totblack;
              END IF;
              
              IF oThisPartVals(nCtrPartVals).totgalv = 0
              THEN
                reco_web_functions.col_span := 1;
                reco_web_functions.cell_attr := vc_Color_OddDayNorm;
                IF MOD(vn_TmpDayCtr,2) = 0
                THEN reco_web_functions.cell_attr := vc_Color_EvenDayNorm;
                END IF;
                reco_web_functions.add_data_column(' ');
              ELSIF oThisPartVals(nCtrPartVals).totgalv != 0
              THEN
                reco_web_functions.col_span := 1;
                reco_web_functions.cell_attr := vc_Color_OddDayNorm;
                IF MOD(vn_TmpDayCtr,2) = 0
                THEN reco_web_functions.cell_attr := vc_Color_EvenDayNorm;
                END IF;
                
                reco_web_functions.add_data_column(
                  TO_CHAR(oThisPartVals(nCtrPartVals).totgalv));
                vn_TmpGPInvQty := vn_TmpGPInvQty -
                  oThisPartVals(nCtrPartVals).totgalv;
              END IF;
              
              nCtrPartVals := nCtrPartVals + 1;
            ELSE
              reco_web_functions.col_span := 1;
              reco_web_functions.cell_attr := vc_Color_OddDayNorm;
              IF MOD(vn_TmpDayCtr,2) = 0
              THEN reco_web_functions.cell_attr := vc_Color_EvenDayNorm;
              END IF;
              reco_web_functions.add_data_column(' ');
              reco_web_functions.add_data_column(' ');
            END IF;
            
          ELSIF oTheSheetColumnInfo(colctr).rptColTypeCode = 'DAYPARTPROPOSEDMFG'
          THEN
            DECLARE
              vn_NumberForCell number;
            BEGIN
              
              SELECT SUM(punrun.qty_bars_processed)
              INTO vn_NumberForCell
              FROM  reco_rstx_calday calday, -- Good:get_date_toshowin_rpt description
                    reco_rstx_punrun_hist punrun,
                    (
                      SELECT DISTINCT
                              subasg.punrun_id,
                              subreq.reqlength,
                              subreq.reqtype,
                              subreq.reqpunch
                      FROM  reco_rstx_punrun_hist subrun,
                            reco_rstx_punreq_hist subreq,
                            reco_rstx_punasg_hist subasg
                      WHERE   subrun.punrun_id = subasg.punrun_id
                      AND     subasg.punreq_id = subreq.punreq_id
                      AND     subrun.cutsch_hist_id = vn_WorkingHistId
                      AND     subasg.cutsch_hist_id = vn_WorkingHistId
                      AND     subreq.cutsch_hist_id = vn_WorkingHistId
                    ) subQPartData
              WHERE   oTheSheetColumnInfo(colctr).shipment_date = calday.thedate
              AND     calday.calday_id = punrun.calday_id
              AND     punrun.cutsch_hist_id = vn_WorkingHistId
              AND     punrun.punrun_id = subQPartData.punrun_id
              AND     subQPartData.reqlength =
                                  rec_CurrPartRow.b_partnumlen
              AND     subQPartData.reqtype =
                                  rec_CurrPartRow.b_parttype
              AND     subQPartData.reqpunch =
                                  rec_CurrPartRow.b_partpunch;
              --NOTE: We do not care about PunchSch coating
              --      because for this report we label all
              --      punching results as black pieces
              
              vn_NumberForCell := NVL(vn_NumberForCell,0);
              
              reco_web_functions.col_span := 1;
              reco_web_functions.cell_attr := vc_Color_OddDayNorm;
              IF MOD(vn_TmpDayCtr,2) = 0
              THEN reco_web_functions.cell_attr := vc_Color_EvenDayNorm;
              END IF;
              IF vn_NumberForCell = 0
              THEN reco_web_functions.add_data_column(' ');
              ELSIF vn_NumberForCell != 0
              THEN reco_web_functions.add_data_column(TO_CHAR(vn_NumberForCell));
              END IF;
              
              vn_TmpBPInvQty := vn_TmpBPInvQty + vn_NumberForCell;
            END;
          
          ELSIF oTheSheetColumnInfo(colctr).rptColTypeCode = 'ENDINVTOTAL'
          THEN
            vn_TmpDayCtr := vn_TmpDayCtr + 1;
            
            reco_web_functions.col_span := 1;
            reco_web_functions.cell_attr := '';
            reco_web_functions.add_data_column(TO_CHAR(vn_TmpBPInvQty));
            
            reco_web_functions.col_span := 1;
            reco_web_functions.cell_attr := '';
            reco_web_functions.add_data_column(TO_CHAR(vn_TmpGPInvQty));
            
         ELSIF oTheSheetColumnInfo(colctr).rptColTypeCode = 'NEGATIVEINV'
          THEN
                      
            reco_web_functions.col_span := 2;
            reco_web_functions.cell_attr := vc_Color_Negative;
            reco_web_functions.add_data_column(getFirstNegativeDateText(sectionorder, vc_PartName));
  
          END IF;
        END LOOP;
      
      ELSIF bSummaryReport THEN
      -- JNL REPORTING CONDITION START
      ----------------------------------------------------------------------------------------------------------------
      ----------------------------------------------------------------------------------------------------------------
        FOR colctr IN 1 .. oTheSheetColumnInfo.count
        LOOP
          IF oTheSheetColumnInfo(colctr).rptColTypeCode = 'PARTNAME'
          THEN
            IF rec_CurrPartRow.sortorder = sectionorder
            THEN
              reco_web_functions.col_span := 1;
              reco_web_functions.cell_attr := vc_Color_InvText;
              reco_web_functions.add_data_column(rec_CurrPartRow.G_PARTNAME);  -- JNL
            ELSE
              reco_web_functions.col_span := 1;
              reco_web_functions.cell_attr := '';
              reco_web_functions.add_data_column(
                rec_CurrPartRow.g_partname);
            END IF;
                              
          ELSIF oTheSheetColumnInfo(colctr).rptColTypeCode = 'DAILYPARTINV'
          THEN
            vn_TmpDayCtr := vn_TmpDayCtr + 1;
            
            IF oTheSheetColumnInfo(colctr).num_child_cols = 3
            THEN
              reco_web_functions.col_span := 1;
              reco_web_functions.cell_attr := vc_Color_OddDayNorm;
              IF MOD(vn_TmpDayCtr,2) = 0
              THEN reco_web_functions.cell_attr := vc_Color_EvenDayNorm;
              END IF;
              IF vn_TmpNPInvQty < 0
                THEN reco_web_functions.cell_attr := vc_Color_Negative;
              END IF;
              
              -- JNL REPORT IF CONDITION
              IF colctr = 2 OR colctr = (oTheSheetColumnInfo.count ) OR colctr = (oTheSheetColumnInfo.count - 1) THEN
                reco_web_functions.add_data_column(TO_CHAR(vn_TmpNPInvQty));
              END IF;
                
            END IF;
            
            reco_web_functions.col_span := 1;
            reco_web_functions.cell_attr := vc_Color_OddDayNorm;
            IF MOD(vn_TmpDayCtr,2) = 0
              THEN reco_web_functions.cell_attr := vc_Color_EvenDayNorm;
            END IF;
            IF vn_TmpBPInvQty < 0
              THEN reco_web_functions.cell_attr := vc_Color_Negative;
            END IF;
            
            -- JNL REPORT IF CONDITION
            IF colctr = 2 OR colctr = (oTheSheetColumnInfo.count ) OR colctr = (oTheSheetColumnInfo.count - 1) THEN
              reco_web_functions.add_data_column(TO_CHAR(vn_TmpBPInvQty));
            END IF;
            
            reco_web_functions.col_span := 1;
            reco_web_functions.cell_attr := vc_Color_OddDayNorm;
            IF MOD(vn_TmpDayCtr,2) = 0
              THEN reco_web_functions.cell_attr := vc_Color_EvenDayNorm;
            END IF;
            
            IF vn_TmpGPInvQty < 0
              THEN reco_web_functions.cell_attr := vc_Color_Negative;
            END IF;
            
            -- JNL REPORT IF CONDITION
            IF colctr = 2 OR colctr = (oTheSheetColumnInfo.count ) OR colctr = (oTheSheetColumnInfo.count - 1) THEN
              reco_web_functions.add_data_column(TO_CHAR(vn_TmpGPInvQty));
            END IF;
            
          ELSIF oTheSheetColumnInfo(colctr).rptColTypeCode = 'DELIVEREDSHIP'
          THEN
            IF nCtrPartVals <= oThisPartVals.count
            AND oThisPartVals(nCtrPartVals).shipment_id =
                  oTheSheetColumnInfo(colctr).shipment_id
            THEN
              IF oThisPartVals(nCtrPartVals).totblack = 0
              THEN
                reco_web_functions.col_span := 1;
                reco_web_functions.cell_attr := vc_Color_DelivStdTxt;
                -- JNL REPORT IF CONDITION
                IF colctr = 2 OR colctr = (oTheSheetColumnInfo.count ) OR colctr = (oTheSheetColumnInfo.count - 1) THEN
                  reco_web_functions.add_data_column(' ');
                END IF;
              ELSIF oThisPartVals(nCtrPartVals).totblack != 0
              THEN
                reco_web_functions.col_span := 1;
                reco_web_functions.cell_attr := vc_Color_BlackSteel;
                 -- JNL REPORT IF CONDITION
                IF colctr = 2 OR colctr = (oTheSheetColumnInfo.count ) OR colctr = (oTheSheetColumnInfo.count - 1) THEN
                  reco_web_functions.add_data_column(
                  TO_CHAR(oThisPartVals(nCtrPartVals).totblack));
                END IF;
                
  --              vn_TmpBPInvQty := vn_TmpBPInvQty -
  --                oThisPartVals(nCtrPartVals).totblack;
              END IF;
              
              IF oThisPartVals(nCtrPartVals).totgalv = 0
              THEN
                reco_web_functions.col_span := 1;
                reco_web_functions.cell_attr := vc_Color_DelivStdTxt;
                -- JNL REPORT IF CONDITION
                IF colctr = 2 OR colctr = (oTheSheetColumnInfo.count ) OR colctr = (oTheSheetColumnInfo.count - 1) THEN
                 reco_web_functions.add_data_column(' ');
                END IF;
                
                
              ELSIF oThisPartVals(nCtrPartVals).totgalv != 0
              THEN
                reco_web_functions.col_span := 1;
                reco_web_functions.cell_attr := vc_Color_DelivStdTxt;
                -- JNL REPORT IF CONDITION
                IF colctr = 2 OR colctr = (oTheSheetColumnInfo.count ) OR colctr = (oTheSheetColumnInfo.count - 1) THEN
                 reco_web_functions.add_data_column(
                  TO_CHAR(oThisPartVals(nCtrPartVals).totgalv));
                END IF;
  
  --              vn_TmpGPInvQty := vn_TmpGPInvQty -
  --                oThisPartVals(nCtrPartVals).totgalv;
              END IF;
              
              nCtrPartVals := nCtrPartVals + 1;
            ELSE
              reco_web_functions.col_span := 1;
              reco_web_functions.cell_attr := vc_Color_DelivStdTxt;
              
               -- JNL REPORT IF CONDITION
                IF colctr = 2 OR colctr = (oTheSheetColumnInfo.count ) OR colctr = (oTheSheetColumnInfo.count - 1) THEN
                 reco_web_functions.add_data_column(' ');
                reco_web_functions.add_data_column(' ');
                END IF;
                
            END IF;
          ELSIF oTheSheetColumnInfo(colctr).rptColTypeCode = 'PENDINGSHIP'
          THEN
            IF nCtrPartVals <= oThisPartVals.count
            AND oThisPartVals(nCtrPartVals).shipment_id =
                  oTheSheetColumnInfo(colctr).shipment_id
            THEN

              IF oThisPartVals(nCtrPartVals).totblack = 0
              THEN
                reco_web_functions.col_span := 1;
                reco_web_functions.cell_attr := vc_Color_OddDayNorm;
                IF MOD(vn_TmpDayCtr,2) = 0
                THEN reco_web_functions.cell_attr := vc_Color_EvenDayNorm;
                END IF;
                
                -- JNL REPORT IF CONDITION
                IF colctr = 2 OR colctr = (oTheSheetColumnInfo.count ) OR colctr = (oTheSheetColumnInfo.count - 1) THEN
                reco_web_functions.add_data_column(' ');
                END IF;
                
              ELSIF oThisPartVals(nCtrPartVals).totblack != 0
              THEN
                reco_web_functions.col_span := 1;
                reco_web_functions.cell_attr := vc_Color_BlackSteel;
                
                -- JNL REPORT IF CONDITION
                IF colctr = 2 OR colctr = (oTheSheetColumnInfo.count ) OR colctr = (oTheSheetColumnInfo.count - 1) THEN
                reco_web_functions.add_data_column(
                  TO_CHAR(oThisPartVals(nCtrPartVals).totblack));
                END IF;
                
                
                vn_TmpBPInvQty := vn_TmpBPInvQty -
                  oThisPartVals(nCtrPartVals).totblack;
              END IF;
              
              IF oThisPartVals(nCtrPartVals).totgalv = 0
              THEN
                reco_web_functions.col_span := 1;
                reco_web_functions.cell_attr := vc_Color_OddDayNorm;
                IF MOD(vn_TmpDayCtr,2) = 0
                THEN reco_web_functions.cell_attr := vc_Color_EvenDayNorm;
                END IF;
                
                -- JNL REPORT IF CONDITION
                IF colctr = 2 OR colctr = (oTheSheetColumnInfo.count ) OR colctr = (oTheSheetColumnInfo.count - 1) THEN
                  reco_web_functions.add_data_column(' ');
                END IF;
                
                
              ELSIF oThisPartVals(nCtrPartVals).totgalv != 0
              THEN
                reco_web_functions.col_span := 1;
                reco_web_functions.cell_attr := vc_Color_OddDayNorm;
                IF MOD(vn_TmpDayCtr,2) = 0
                THEN reco_web_functions.cell_attr := vc_Color_EvenDayNorm;
                END IF;
                
                -- JNL REPORT IF CONDITION
                IF colctr = 2 OR colctr = (oTheSheetColumnInfo.count ) OR colctr = (oTheSheetColumnInfo.count - 1) THEN
                  reco_web_functions.add_data_column(
                  TO_CHAR(oThisPartVals(nCtrPartVals).totgalv));
                END IF;
                
                
                vn_TmpGPInvQty := vn_TmpGPInvQty -
                  oThisPartVals(nCtrPartVals).totgalv;
              END IF;
              
              nCtrPartVals := nCtrPartVals + 1;
            ELSE
              reco_web_functions.col_span := 1;
              reco_web_functions.cell_attr := vc_Color_OddDayNorm;
              IF MOD(vn_TmpDayCtr,2) = 0
              THEN reco_web_functions.cell_attr := vc_Color_EvenDayNorm;
              END IF;
              
                -- JNL REPORT IF CONDITION
                IF colctr = 2 OR colctr = (oTheSheetColumnInfo.count ) OR colctr = (oTheSheetColumnInfo.count - 1) THEN
                  reco_web_functions.add_data_column(' ');
                  reco_web_functions.add_data_column(' ');
                END IF;
                  
            END IF;
            
          ELSIF oTheSheetColumnInfo(colctr).rptColTypeCode = 'DAYPARTPROPOSEDMFG'
          THEN
            DECLARE
              vn_NumberForCell number;
            BEGIN
              
              SELECT SUM(punrun.qty_bars_processed)
              INTO vn_NumberForCell
              FROM  reco_rstx_calday calday, -- Good:get_date_toshowin_rpt description
                    reco_rstx_punrun_hist punrun,
                    (
                      SELECT DISTINCT
                              subasg.punrun_id,
                              subreq.reqlength,
                              subreq.reqtype,
                              subreq.reqpunch
                      FROM  reco_rstx_punrun_hist subrun,
                            reco_rstx_punreq_hist subreq,
                            reco_rstx_punasg_hist subasg
                      WHERE   subrun.punrun_id = subasg.punrun_id
                      AND     subasg.punreq_id = subreq.punreq_id
                      AND     subrun.cutsch_hist_id = vn_WorkingHistId
                      AND     subasg.cutsch_hist_id = vn_WorkingHistId
                      AND     subreq.cutsch_hist_id = vn_WorkingHistId
                    ) subQPartData
              WHERE   oTheSheetColumnInfo(colctr).shipment_date = calday.thedate
              AND     calday.calday_id = punrun.calday_id
              AND     punrun.cutsch_hist_id = vn_WorkingHistId
              AND     punrun.punrun_id = subQPartData.punrun_id
              AND     subQPartData.reqlength =
                                  rec_CurrPartRow.b_partnumlen
              AND     subQPartData.reqtype =
                                  rec_CurrPartRow.b_parttype
              AND     subQPartData.reqpunch =
                                  rec_CurrPartRow.b_partpunch;
              --NOTE: We do not care about PunchSch coating
              --      because for this report we label all
              --      punching results as black pieces
              
              vn_NumberForCell := NVL(vn_NumberForCell,0);
              
              reco_web_functions.col_span := 1;
              reco_web_functions.cell_attr := vc_Color_OddDayNorm;
              IF MOD(vn_TmpDayCtr,2) = 0
              THEN reco_web_functions.cell_attr := vc_Color_EvenDayNorm;
              END IF;
              IF vn_NumberForCell = 0
              THEN 
                -- JNL REPORT IF CONDITION
                IF colctr = 2 OR colctr = (oTheSheetColumnInfo.count ) OR colctr = (oTheSheetColumnInfo.count - 1) THEN
                  reco_web_functions.add_data_column(' ');
                END IF;
                
              ELSIF vn_NumberForCell != 0
              THEN 
                -- JNL REPORT IF CONDITION
                IF colctr = 2 OR colctr = (oTheSheetColumnInfo.count ) OR colctr = (oTheSheetColumnInfo.count - 1) THEN
                  reco_web_functions.add_data_column(TO_CHAR(vn_NumberForCell));
                END IF;
                
              END IF;
              
              vn_TmpBPInvQty := vn_TmpBPInvQty + vn_NumberForCell;
            END;  
          
          ELSIF oTheSheetColumnInfo(colctr).rptColTypeCode = 'ENDINVTOTAL'
          THEN
            vn_TmpDayCtr := vn_TmpDayCtr + 1;
            
            reco_web_functions.col_span := 1;
            reco_web_functions.cell_attr := '';
            
            -- JNL REPORT IF CONDITION
            IF colctr = (oTheSheetColumnInfo.count ) OR colctr = (oTheSheetColumnInfo.count - 1) THEN
              reco_web_functions.add_data_column(TO_CHAR(vn_TmpBPInvQty));
            END IF;
           
            reco_web_functions.col_span := 1;
            reco_web_functions.cell_attr := '';
            
            -- JNL REPORT IF CONDITION
            IF colctr = (oTheSheetColumnInfo.count ) OR colctr = (oTheSheetColumnInfo.count - 1) THEN
              reco_web_functions.add_data_column(TO_CHAR(vn_TmpGPInvQty));
            END IF;
            
         ELSIF oTheSheetColumnInfo(colctr).rptColTypeCode = 'NEGATIVEINV'
          THEN
                      
            reco_web_functions.col_span := 2;
            reco_web_functions.cell_attr := vc_Color_Negative;
            
            -- JNL REPORT IF CONDITION
            IF colctr = (oTheSheetColumnInfo.count )THEN
              reco_web_functions.add_data_column(getFirstNegativeDateText(sectionorder, vc_PartName));
          END IF;
          
          END IF;
        END LOOP;
      ----------------------------------------------------------------------------------------------------------------
      ----------------------------------------------------------------------------------------------------------------
      END IF;
      -- JNL REPORTING CONDITION END
      
      reco_web_functions.print_datarow;
      
      vb_PrevPartRowExists := TRUE;
      vr_PrevPartRow := rec_CurrPartRow;
    
    END LOOP; 
  
       IF sectionorder = 1 THEN proc_PrintTwoWeightsRowsSP('S504%');
    ELSIF sectionorder = 2 THEN proc_PrintTwoWeightsRowsSP('D504%'); 
    ELSIF sectionorder = 3 THEN proc_PrintTwoWeightsRowsSP('S506%'); 
    ELSIF sectionorder = 4 THEN proc_PrintTwoWeightsRowsSP('D506%');      
    ELSE proc_PrintTwoWeightsRowsSP('');
    END IF;
    
END;

    BEGIN -- Body - Print part rows
      IF NVL(fnd_global.org_id,-1) <> 0 THEN
        get_reco_organization('0');
        END IF;
      printsection(1);
      printsection(2);
      printsection(3);
      printsection(4);
      printsection(5);
    
    END; -- Body - Print part rows
  
  reco_web_Functions.close_spreadsheet;
  
EXCEPTION
 WHEN others
 THEN
   htp.tableclose;
   htp.print('Report Exception Condition:'||thelocation||'-'||sqlerrm|| -- CONTINUE HERE ADD TO OTHER FUNCTS
            ' Date:'||TO_CHAR(SYSDATE,'DD-MON-YYYY'));
   htp.htmlClose;
   
END; -- rstx_shipcal_bydate_rpt
--------------------------------------------

--------------------------------------------------------------------------------
PROCEDURE rstx_shipcal_rpt( pi_QtyWeeks IN varchar2,
                            pi_RoundToEndOfWeek IN varchar2,
                            pi_GivenHistId IN varchar2)
IS
  TYPE rec_SheetColumnInfo IS record
            ( rptColTypeCode varchar2(30),
              num_child_cols number,
              shipment_date reco_shipment.shipment_date%TYPE,
              tracking_number reco_shipment.tracking_number%TYPE,
              shipment_status reco_shipment.shipment_status%TYPE,
              shipment_id reco_shipment.shipment_id%TYPE,
              STATE reco_shipping_addresses_v.state%TYPE,
              daystrt_npb_tonn number,
              daystrt_spb_tonn number,
              daystrt_spg_tonn number,
              daystrt_dpb_tonn number,
              daystrt_dpg_tonn number,
              
              daystrt506_npb_tonn number,
              daystrt506_spb_tonn number,
              daystrt506_spg_tonn number,
              daystrt506_dpb_tonn number,
              daystrt506_dpg_tonn number,
              
              vcFirstNegativeDateText varchar2(30),
              
              ship_stlwgt number,
              ship_stlwgtDP number,
              ship_totwgt number,
              day_manuf_spb_tonn number,
              day_manuf_dpb_tonn number);
  
  TYPE coll_SheetColumnInfo IS TABLE OF rec_SheetColumnInfo;
  --oTheSheetColumnInfo coll_SheetColumnInfo; -- Fetched, so don't initialize
  oTheSheetColumnInfo coll_SheetColumnInfo := coll_SheetColumnInfo();
  oTheSheetColumnInfoSP coll_SheetColumnInfo := coll_SheetColumnInfo();
  oTheSheetColumnInfoDP coll_SheetColumnInfo := coll_SheetColumnInfo();
                                        -- Initialize since not fetched
  nCtrSheetColumnInfo number;
  thelocation   varchar2(80);
--  type rec_PartNameAndInv is record
--            ( n_partid reco_rstx_originvqty_hist.inventory_item_id%type,
--              n_partname reco_rstx_originvqty_hist.segment1%type,
--              n_partpunch reco_rstx_originvqty_hist.thepunch%type,
--              n_parttype reco_rstx_originvqty_hist.thetype%type,
--              n_partcoat reco_rstx_originvqty_hist.thecoat%type,
--              n_partnumlen reco_rstx_originvqty_hist.numlength%type,
--              n_partcharlen reco_rstx_originvqty_hist.charlength%type,
--              n_originvqty reco_rstx_originvqty_hist.quantity%type,
--              b_partid reco_rstx_originvqty_hist.inventory_item_id%type,
--              b_partname reco_rstx_originvqty_hist.segment1%type,
--              b_partpunch reco_rstx_originvqty_hist.thepunch%type,
--              b_parttype reco_rstx_originvqty_hist.thetype%type,
--              b_partcoat reco_rstx_originvqty_hist.thecoat%type,
--              b_partnumlen reco_rstx_originvqty_hist.numlength%type,
--              b_partcharlen reco_rstx_originvqty_hist.charlength%type,
--              b_originvqty reco_rstx_originvqty_hist.quantity%type,
--              g_partid reco_rstx_originvqty_hist.inventory_item_id%type,
--              g_partname reco_rstx_originvqty_hist.segment1%type,
--              g_partpunch reco_rstx_originvqty_hist.thepunch%type,
--              g_parttype reco_rstx_originvqty_hist.thetype%type,
--              g_partcoat reco_rstx_originvqty_hist.thecoat%type,
--              g_partnumlen reco_rstx_originvqty_hist.numlength%type,
--              g_partcharlen reco_rstx_originvqty_hist.charlength%type,
--              g_originvqty reco_rstx_originvqty_hist.quantity%type,
--              groupnumber number);
--  
--  type coll_PartNameAndInv is table of rec_PartNameAndInv;
--  --oThePartNameAndInv coll_PartNameAndInv; -- Fetched, so don't initialize
--  oThePartNameAndInv coll_PartNameAndInv := coll_PartNameAndInv();
--                                        -- Initialize since not fetched
--  --nCtrPartNameAndInv number;
  
  vn_WorkingHistId number;
  vc_WorkingHistUser reco_rstx_cutsch_hist.theusername%TYPE;
  vd_WorkingHistDate date;
  vn_MaxRecentHistId number;
  vc_MaxRecentHistUser reco_rstx_cutsch_hist.theusername%TYPE;
  vd_MaxRecentHistDate date;
  
  vr_Params reco_rstx_userparam_hist%ROWTYPE;
  
  vn_QtyColumnsInSpreadsheet number; -- This gets set when finding column info
  
  vc_Color_OddDayNorm varchar2(80);
  vc_Color_EvenDayNorm varchar2(80);
  vc_Color_BlackSteel varchar2(80);
  vc_Color_Negative varchar2(80);
  vc_Color_InvText varchar2(80);
  vc_Color_DelivStdTxt varchar2(80);
  
  vd_FirstDateShown date;
  vd_LastDateShown date;
 
-- ----------------------------------------------------------------------------- JNL FUNCTION START
-- -----------------------------------------------------------------------------
FUNCTION WeightForPartType ( p_shipmentId IN NUMBER,
                             p_partTypeToUse IN VARCHAR2)
RETURN number
IS
   sumTotal number;

   CURSOR c_getTotal IS
   SELECT SUM(subrspv.calc_tons) totwgt
   FROM   reco_shipment_parts_v subrspv
   WHERE  subrspv.SHIPMENT_ID  = p_shipmentId
     AND  subrspv.PART_NAME LIKE p_partTypeToUse ;

BEGIN

   OPEN c_getTotal;
   FETCH c_getTotal INTO sumTotal;

   IF c_getTotal%notfound THEN
      sumTotal := 0;
   END IF;

   CLOSE c_getTotal;

RETURN sumTotal;

EXCEPTION
WHEN OTHERS THEN
   raise_application_error(-20001,'An error was encountered - '||SQLCODE||' -ERROR- '||SQLERRM);
END;
-- -----------------------------------------------------------------------------
-- ----------------------------------------------------------------------------- JNL FUNCTION END  
  --vn_TmpDayCtr number;
BEGIN -- rstx_shipcal_rpt
  thelocation := 'begin';
  get_Reco_organization('0');  -- force to RECO US
  -- 
  -- Special History note:
  -- 
  -- We only use the HISTORY_ID in this method for calculating
  -- the PART ORIGINAL INVENTORY, and nothing else -- CONTINUE HERE
  -- 
  -- Try to grab the inventory from start of day
  -- (The cutschedule ID of user NIGHTLY AUTO REFRESH)
  -- 
  -- If that doesn't work then just use current inventory
  -- (still print an error so we know what happened)
  
  DECLARE
    vn_TmpQtyRows number;
  BEGIN
    SELECT COUNT(*) INTO vn_TmpQtyRows FROM reco_rstx_cutsch_hist;
    IF NVL(vn_TmpQtyRows,0) = 0
    THEN
      reco_web_functions.reset_sheet;
      reco_web_functions.table_attr := 'border="1" frame="border" rules="all"';
--      reco_web_functions.open_spreadsheet; 
      reco_web_functions.open_spreadsheet('NODATE:reco_steel_shipments_report'); --Added by RS on 03/04/2026.
      reco_web_functions.col_span := 10;
      reco_web_functions.add_header_column(
        'Internal Error 2070 - Invalid History / Info. Contact MIS.');
      reco_web_functions.print_header;
      reco_web_Functions.close_spreadsheet;
      RETURN;
    END IF;
  END;
  
  SELECT cutsch_hist_id, thetime, theusername
  INTO vn_MaxRecentHistId, vd_MaxRecentHistDate, vc_MaxRecentHistUser
  FROM reco_rstx_cutsch_hist
  WHERE cutsch_hist_id IN
                  ( SELECT MAX(cutsch_hist_id)
                    FROM reco_rstx_cutsch_hist );
  
  vn_WorkingHistId := vn_MaxRecentHistId;
  vc_WorkingHistUser := vc_MaxRecentHistUser;
  vd_WorkingHistDate := TRUNC(vd_MaxRecentHistDate);
  
  ---
  -- Access user parameters
  ---
  
  BEGIN
    SELECT * INTO vr_Params
    FROM reco_rstx_userparam_hist WHERE cutsch_hist_id = vn_WorkingHistId;
    
    IF vr_Params.min_cut_allowed IS NULL
    OR vr_Params.max_cut_allowed IS NULL
    OR vr_Params.first_date_of_reqs IS NULL
    OR vr_Params.first_date_of_cutting IS NULL
    OR vr_Params.first_date_of_cutting < vr_Params.first_date_of_reqs
    THEN RAISE NO_DATA_FOUND;
    END IF;
    
    -- MARCH 2013 - Added to synch Excel report with Row number
    IF vr_Params.min_cut_allowed != 5
    THEN vr_Params.min_cut_allowed := 5;
    END IF;
  EXCEPTION
    WHEN others
    THEN
      reco_web_functions.reset_sheet;
      reco_web_functions.table_attr := 'border="1" frame="border" rules="all"';
--      reco_web_functions.open_spreadsheet; 
      reco_web_functions.open_spreadsheet('NODATE:reco_steel_shipments_report'); --Added by RS on 03/04/2026.
      reco_web_functions.col_span := 10;
      reco_web_functions.add_header_column(
      'Internal Error 2031 - User params inaccessible. Contact MIS');
      reco_web_functions.print_header;
      reco_web_Functions.close_spreadsheet;
      RETURN;
  END;
  
  ---
  -- Determine cell colors
  ---
  
  vc_Color_OddDayNorm := 'bgcolor = #F7FFBB';
  vc_Color_EvenDayNorm := 'bgcolor = #B3FBBF';
  vc_Color_BlackSteel := 'bgcolor =#000000 <font color=WHITE';
  vc_Color_Negative := 'bgcolor =#FFFFFF <font color=RED';
  vc_Color_InvText := '<font color=BLUE';
  vc_Color_DelivStdTxt := 'bgcolor =#C0C0C0 <font color=BLACK';
  
  ---
  -- Determine first report date, last report date, and other parameters
  ---
  
  SELECT  MIN(calday.thedate) INTO vd_FirstDateShown
  FROM  reco_rstx_calday calday -- Good:see get_date_toshowin_rpt description
  WHERE   calday.thedate >= vr_Params.first_date_of_reqs
  AND     calday.thedate < vr_Params.first_date_of_cutting
  AND     EXISTS (SELECT  1
                  FROM  reco_truck rs,
                        reco_truckstop_parts rsp,
                        reco_rstx_originvqty_hist roiq
                  WHERE   roiq.inventory_item_id = rsp.part_id
                  AND     rsp.orig_subinventory_code = 'RSTX'
                  AND     rsp.stop_truck_id = rs.truck_id
                  AND     rs.truck_status IN ('A','H','B')
                  AND     rs.truck_date = calday.thedate
                  AND     roiq.cutsch_hist_id = vn_WorkingHistId);
  
  vd_FirstDateShown := NVL(vd_FirstDateShown,vr_Params.first_date_of_cutting);
  
  vd_LastDateShown :=
      vd_FirstDateShown + (TO_NUMBER(NVL(pi_QtyWeeks,2) * 7));
	  
  
  IF vd_FirstDateShown IS NULL OR vd_LastDateShown IS NULL
  THEN
    reco_web_functions.reset_sheet;
    reco_web_functions.table_attr := 'border="1" frame="border" rules="all"';
--    reco_web_functions.open_spreadsheet;
    reco_web_functions.open_spreadsheet('NODATE:reco_steel_shipments_report'); --Added by RS on 03/04/2026. 
    reco_web_functions.col_span := 10;
    reco_web_functions.add_header_column(
    'Internal Error 2045 - Date is invalid or corrupt. Contact MIS');
    reco_web_functions.print_header;
    reco_web_Functions.close_spreadsheet;
    RETURN;
  END IF;
  
  IF UPPER(pi_RoundToEndOfWeek) LIKE 'T%'
  THEN
    LOOP
      IF TO_CHAR(vd_LastDateShown,'DY') = 'SUN'
      THEN exit;
      END IF;
      
      vd_LastDateShown := vd_LastDateShown + 1;
    END LOOP;
  END IF;
  
  ---
  -- Set values for: reco_rstx_tmpshpcalparts
  -- (This table represents the part-row information in our spreadsheet)
  -- 
  -- NOTE #1 - PERFORMANCE
  -- We only need to refresh reco_rstx_tmpshpcalparts if the parts
  -- could have changed (e.g. the cutsch was refreshed)
  -- 
  -- NOTE #2
  -- This does not include any blank lines between rows
  ---
  
  DECLARE
    vb_ForceRptRefresh BOOLEAN;
    vn_PreviousCutSchHistId number;
  BEGIN
    
    vb_ForceRptRefresh := FALSE;
    
    BEGIN
      SELECT prev_rpt_cutsch_hist_id
      INTO vn_PreviousCutSchHistId
      FROM reco_rstx_lastshpcalrun;
    EXCEPTION
      WHEN NO_DATA_FOUND
      THEN
        vb_ForceRptRefresh := TRUE; 
        vn_PreviousCutSchHistId := -1;
      WHEN others
      THEN
        reco_web_functions.reset_sheet;
        reco_web_functions.table_attr := 'border="1" frame="border" rules="all"';
--        reco_web_functions.open_spreadsheet; 
        reco_web_functions.open_spreadsheet('NODATE:reco_steel_shipments_report'); --Added by RS on 03/04/2026.
        reco_web_functions.col_span := 10;
        reco_web_functions.add_header_column(
          'Internal Error 2074 - Internal tracking '||
          'of reports is corrupted. Contact MIS');
        reco_web_functions.print_header;
        reco_web_Functions.close_spreadsheet;
        RETURN;
    END;
    
    IF vb_ForceRptRefresh = TRUE
    OR vn_WorkingHistId != vn_PreviousCutSchHistId
    THEN
      DELETE FROM reco_rstx_tmpshpcalparts;
      
      -- refresh the part records / table row information
      INSERT INTO reco_rstx_tmpshpcalparts
      ( N_PARTID,N_PARTNAME,N_PARTPUNCH,N_PARTTYPE,
        N_PARTCOAT,N_PARTNUMLEN,N_PARTCHARLEN,N_ORIGINVQTY,
        B_PARTID,B_PARTNAME,B_PARTPUNCH,B_PARTTYPE,
        B_PARTCOAT,B_PARTNUMLEN,B_PARTCHARLEN,B_ORIGINVQTY,
        G_PARTID,G_PARTNAME,G_PARTPUNCH,G_PARTTYPE,
        G_PARTCOAT,G_PARTNUMLEN,G_PARTCHARLEN,G_ORIGINVQTY,
        SORTORDER
      )
      (
        SELECT  nopunroiq.inventory_item_id n_partid,
                NVL(nopunroiq.segment1,'N'||galvroiq.thetype||
                                       'B'||galvroiq.charlength) n_partname,
                NVL(nopunroiq.thepunch,'N') n_partpunch,
                NVL(nopunroiq.thetype,galvroiq.thetype) n_parttype,
                NVL(nopunroiq.thecoat,'B') n_partcoat,
                NVL(nopunroiq.numlength,galvroiq.numlength) n_partnumlen,
                NVL(nopunroiq.charlength,galvroiq.charlength) n_partcharlen,
                NVL(nopunroiq.quantity,0) n_originvqty,
                blackroiq.inventory_item_id b_partid,
                NVL(blackroiq.segment1,galvroiq.thepunch||galvroiq.thetype||
                                       'B'||galvroiq.charlength) b_partname,
                NVL(blackroiq.thepunch,'N') b_partpunch,
                NVL(blackroiq.thetype,galvroiq.thetype) b_parttype,
                NVL(blackroiq.thecoat,'B') b_partcoat,
                NVL(blackroiq.numlength,galvroiq.numlength) b_partnumlen,
                NVL(blackroiq.charlength,galvroiq.charlength) b_partcharlen,
                NVL(blackroiq.quantity,0) b_originvqty,
                galvroiq.inventory_item_id g_partid,
                galvroiq.segment1 g_partname,
                galvroiq.thepunch g_partpunch,
                galvroiq.thetype g_parttype,
                galvroiq.thecoat g_partcoat,
                galvroiq.numlength g_partnumlen,
                galvroiq.charlength g_partcharlen,
                galvroiq.quantity g_originvqty,
                CASE
                  WHEN galvroiq.thepunch = 'S'
                  AND galvroiq.thetype = '504'                             
                  AND galvroiq.numlength >= vr_Params.min_cut_allowed
                  AND galvroiq.numlength <= vr_Params.max_cut_allowed
                  THEN 1
                  WHEN galvroiq.thepunch = 'D'
                  AND galvroiq.thetype = '504'                             
                  AND galvroiq.numlength >= vr_Params.min_cut_allowed
                  AND galvroiq.numlength <= vr_Params.max_cut_allowed
                  THEN 2
                  WHEN galvroiq.thepunch = 'S'
                  AND galvroiq.thetype = '506'                             
                  AND galvroiq.numlength >= vr_Params.min_cut_allowed
                  AND galvroiq.numlength <= vr_Params.max_cut_allowed
                  THEN 3
                  WHEN galvroiq.thepunch = 'D'
                  AND galvroiq.thetype = '506'                             
                  AND galvroiq.numlength >= vr_Params.min_cut_allowed
                  AND galvroiq.numlength <= vr_Params.max_cut_allowed
                  THEN 4
                  ELSE 5
                END sortorder
        FROM  reco_rstx_originvqty_hist nopunroiq,
              reco_rstx_originvqty_hist blackroiq,
              reco_rstx_originvqty_hist galvroiq
        WHERE   galvroiq.category_set_id = nCSetG
        AND     galvroiq.inventory_item_id IS NOT NULL
        AND     galvroiq.cutsch_hist_id = vn_WorkingHistId
        AND     galvroiq.actual_attribute4 = blackroiq.segment1 (+)
        AND     blackroiq.category_set_id (+) = nCSetB
        AND     blackroiq.cutsch_hist_id (+) = vn_WorkingHistId
        AND     'N'||galvroiq.thetype||'B'||galvroiq.charlength
                              = nopunroiq.segment1 (+)
        AND     nopunroiq.category_set_id (+) = nCSetN
        AND     nopunroiq.cutsch_hist_id (+) = vn_WorkingHistId
      );
      
      COMMIT;
    END IF;
  END;
  thelocation := 'refresh';  
  ---
  -- Cache our current cutsch_hist_id into reco_rstx_lastshpcalrun table
  ---
  
  DECLARE
    vn_TmpNumRows number; -- Should always be 1
  BEGIN
    UPDATE reco_rstx_lastshpcalrun
    set prev_rpt_cutsch_hist_id = vn_WorkingHistId;
    
    vn_TmpNumRows := SQL%ROWCOUNT;
    
    IF vn_TmpNumRows > 1
    THEN
      reco_web_functions.reset_sheet;
      reco_web_functions.table_attr := 'border="1" frame="border" rules="all"';
--      reco_web_functions.open_spreadsheet;
      reco_web_functions.open_spreadsheet('NODATE:reco_steel_shipments_report'); --Added by RS on 03/04/2026. 
      reco_web_functions.col_span := 10;
      reco_web_functions.add_header_column(
        'Internal Error 2075 - Caching Table is corrupted. Contact MIS');
      reco_web_functions.print_header;
      reco_web_Functions.close_spreadsheet;
      RETURN;
    ELSIF vn_TmpNumRows = 0
    THEN
      INSERT INTO reco_rstx_lastshpcalrun(prev_rpt_cutsch_hist_id)
      VALUES (vn_WorkingHistId);
    END IF;
    
    COMMIT;
  END;  
    thelocation := 'lastrun';
  ---
  -- Set values for: oTheSheetColumnInfo
  -- 
  -- The values in oTheSheetColumnInfo represent each cell in the
  -- 2nd row of the spreadsheet (the row with shipment names in it)
  -- 
  -- Determine Report Column information: days / shipments / inventory numbers
  -- Order is similar to:
  -- PARTNAME
  --        ->
  --      Repeat(DAILYPARTINV -> DELIVEREDSHIP -> PENDINGSHIP -> DAYPARTPROPOSEDMFG)
  --            ->
  --                ENDINVTOTAL
  ---
  
  ---
  -- And vn_QtyColumnsInSpreadsheet gets set as well
  ---

  DECLARE
    CURSOR cur_ColData (pi_FirstDate IN date,
                        pi_LastDate IN date,
                        pi_CurHistoryId IN number,
                        pi_sortOrder IN NUMBER, pi_sortOrder2 IN NUMBER, 
                        pi_sortorder3 number, pi_sortorder4 number, pi_sortorder5 number)        -- JNL
    IS
      -- Retreive a spot in collection for PartName (first column spot)
      SELECT  1 sort_OverallLayout,
              NULL shipment_date,
              NULL sort_DayInvQty_Ship_Mfg,
              NULL sort_DelivShip_Or_Not,
              'PARTNAME' rptColTypeCode, 
              ' ' vcFirstNegativeDateText,
              1 num_child_cols,
              NULL tracking_number,
              NULL shipment_status,
              NULL shipment_id,
              NULL STATE,
              NULL ship_stlwgt,
              NULL ship_stlwgtDP,
              NULL ship_totwgt
      FROM  dual
      -- Retreive a spot for INV label on each date (each date's INV column)
      UNION
      SELECT  2 sort_OverallLayout,
              calday.thedate shipment_date,
              1 sort_DayInvQty_Ship_Mfg,
              NULL sort_DelivShip_Or_Not,
              'DAILYPARTINV' rptColTypeCode, 
              ' ' vcFirstNegativeDateText,
              CASE
              WHEN calday.thedate = pi_FirstDate
              THEN 3
              ELSE 2
              END num_child_cols,
              NULL tracking_number,
              NULL shipment_status,
              NULL shipment_id,
              NULL STATE,
              NULL ship_stlwgt,
              NULL ship_stlwgtDP,
              NULL ship_totwgt
      FROM  reco_rstx_calday calday -- Good:see get_date_toshowin_rpt description
      WHERE   calday.thedate >= pi_FirstDate
      AND     calday.thedate <= pi_LastDate
      -- Retreive a spot for each day's DELIVERED shipments
      UNION
      SELECT  /*+ USE_NL( rs,rsav,subQSteelWgt,subQTotWgt) */ 2 sort_OverallLayout,
              rs.truck_date shipment_date,
              2 sort_DayInvQty_Ship_Mfg,
              1 sort_DelivShip_Or_Not,
              'DELIVEREDSHIP' rptColTypeCode, 
              ' ' vcFirstNegativeDateText,
              2 num_child_cols,
              NVL(rs.tracking_number,rsav.stop_identifier) tracking_number,
              rs.truck_status shipment_status,
              rsav.shipment_id shipment_id,
              rsav.state STATE,
              subQSteelWgt.stlwgt ship_stlwgt,
              subQSteelWgt.stlwgt ship_stlwgtDP,
              subQTotWgt.totwgt ship_totwgt
      FROM  reco_truck rs,
            reco_truckstop_v rsav,
            (
              SELECT  /*+ USE_NL( subrs,ts,subrsp,subQPartsToSum) */ ts.shipment_id,
                      SUM(subrsp.calc_tons) stlwgt
              FROM  reco_truckstop ts, reco_truckstop_parts subrsp,
                    reco_truck subrs,
                    (
                      SELECT n_partid partid FROM reco_rstx_tmpshpcalparts
                      WHERE sortorder IN (1,2,3,4,5)  -- JNL TEST in 1 -- (1,2)
                      UNION
                      SELECT b_partid partid FROM reco_rstx_tmpshpcalparts
                      WHERE sortorder IN (1,2,3,4,5)  -- JNL TEST in 1 -- (1,2)
                      UNION
                      SELECT g_partid partid FROM reco_rstx_tmpshpcalparts
                      WHERE sortorder IN (1,2,3,4,5)  -- JNL TEST in 1 -- (1,2)
                    ) subQPartsToSum -- Verify part relevancy
              WHERE   subrs.truck_id = ts.stop_truck_id
              AND     subrsp.stop_truck_id = ts.stop_truck_id
              AND     subrsp.stop_order_id = ts.stop_order_id
              AND     subrsp.part_id = subQPartsToSum.partid
              AND     subrs.truck_date >= TO_DATE('22-sep-20')
              AND     subrs.truck_date <= TO_DATE('05-oct-20')
              AND     subrs.truck_status IN ('D')
              AND     subrsp.orig_subinventory_code = 'RSTX'
              --and     subroiq.cutsch_hist_id = pi_CurHistoryId
              GROUP BY  ts.shipment_id
            ) subQSteelWgt,
            (
              SELECT  /*+ USE_NL( subrs,ts,subrsp,submsib ) */ ts.shipment_id,
                      SUM(subrsp.calc_tons) totwgt
             FROM  reco_truckstop ts, reco_truckstop_parts subrsp,
                   reco_truck subrs,
                    apps.mtl_system_items_b_kfv submsib
                        -- do not use reco_rstx_originvqty_hist here, cause we need
                        -- ALL parts, and not just steel parts for the total weight
              WHERE   subrs.truck_id = ts.stop_truck_id
              AND    subrsp.stop_truck_id = ts.stop_Truck_id
              AND    subrsp.stop_order_id = ts.stop_order_id
              AND     subrsp.part_id = submsib.inventory_item_id AND submsib.organization_id = 0
              AND     subrs.truck_date >= pi_FirstDate
              AND     subrs.truck_date <= pi_LastDate
              AND     subrs.truck_status IN ('D')
              AND     submsib.inventory_item_status_code = 'Active'
              GROUP BY  ts.shipment_id
            ) subQTotWgt
      WHERE   rs.truck_id = rsav.stop_truck_id
      AND     rsav.shipment_id = subQSteelWgt.shipment_id
      AND     rsav.shipment_id = subQTotWgt.shipment_id
      AND     rs.truck_date >= pi_FirstDate
      AND     rs.truck_date <= pi_LastDate
      AND     rs.truck_status IN ('D')
      AND     EXISTS (SELECT /* USE_NL( roiq,rsp ) */ 'Y'
                      FROM  reco_truckstop ts, reco_truckstop_parts rsp,
                            reco_rstx_originvqty_hist roiq
                      WHERE   rsav.shipment_id = ts.shipment_id
                      AND     rsp.stop_truck_id = ts.stop_truck_id
                      AND     rsp.stop_order_id = ts.stop_order_id
                      AND     rsp.part_id = roiq.inventory_item_id
                      AND     rsp.orig_subinventory_code = 'RSTX'
                      AND     roiq.cutsch_hist_id = pi_CurHistoryId)
      -- Retreive a spot for each day's PENDING shipments
      UNION
      SELECT  2 sort_OverallLayout,
              rs.truck_date shipment_date,
              2 sort_DayInvQty_Ship_Mfg,
              2 sort_DelivShip_Or_Not,
              'PENDINGSHIP' rptColTypeCode, 
              ' ' vcFirstNegativeDateText,
              2 num_child_cols,
              NVL(rs.tracking_number,rsav.stop_identifier) tracking_number,
              rs.truck_status shipment_status,
              rsav.shipment_id shipment_id,
              rsav.state STATE,
              subQSteelWgt.stlwgt ship_stlwgt,
              subQSteelWgt.stlwgt ship_stlwgtDP,
              subQTotWgt.totwgt ship_totwgt
      FROM  reco_truck rs,
            reco_truckstop_v rsav,
            (
              SELECT  /*+ USE_NL(subrs,ts,subrsp,subqpartstosum) */ts.shipment_id,
                      SUM(subrsp.calc_tons) stlwgt
              FROM  reco_truckstop ts, reco_truckstop_parts subrsp,
                    reco_truck subrs,
                    (
                      SELECT n_partid partid FROM reco_rstx_tmpshpcalparts
                      WHERE sortorder IN (pi_sortOrder , pi_sortOrder2, pi_sortorder3, pi_sortorder4,pi_sortorder5)  -- JNL TEST in 1 -- (1,2)
                      UNION
                      SELECT b_partid partid FROM reco_rstx_tmpshpcalparts
                      WHERE sortorder IN (pi_sortOrder , pi_sortOrder2, pi_sortorder3, pi_sortorder4,pi_sortorder5)  -- JNL TEST in 1 -- (1,2)
                      UNION
                      SELECT g_partid partid FROM reco_rstx_tmpshpcalparts
                      WHERE sortorder IN (pi_sortOrder , pi_sortOrder2, pi_sortorder3, pi_sortorder4,pi_sortorder5)  -- JNL TEST in 1 -- (1,2)
                    ) subQPartsToSum -- Verify part relevancy
              WHERE   subrs.truck_id = ts.stop_truck_id
              AND     subrsp.stop_truck_id = ts.stop_truck_id
              AND     subrsp.stop_order_id = ts.stop_order_id
              AND     subrsp.part_id = subQPartsToSum.partid
              AND     subrs.truck_date >= pi_FirstDate
              AND     subrs.truck_date <= pi_LastDate
              AND     subrs.truck_status IN ('A','H','B')
              AND     subrsp.orig_subinventory_code = 'RSTX'
              GROUP BY  ts.shipment_id
            ) subQSteelWgt,
            (
              SELECT  /*+ USE_NL( subrs,ts,subrsp,submsib ) */ts.shipment_id,
                      SUM(subrsp.calc_tons) totwgt
              FROM  reco_truckstop ts, reco_truckstop_parts subrsp,
                    reco_truck subrs,
                    apps.mtl_system_items_b_kfv submsib
                        -- do not use reco_rstx_originvqty_hist here, cause we need
                        -- ALL parts, and not just steel parts for the total weight
              WHERE   subrs.truck_id = ts.stop_truck_id
              AND     subrsp.stop_Truck_id = ts.stop_truck_id
              AND     subrsp.stop_order_id = ts.stop_order_id
              AND     subrsp.part_id = submsib.inventory_item_id AND submsib.organization_id = 0
              AND     subrs.truck_date >= pi_FirstDate
              AND     subrs.truck_date <= pi_LastDate
              AND     subrs.truck_status IN ('A','H','B')
              AND     submsib.inventory_item_status_code = 'Active'
              GROUP BY  ts.shipment_id
            ) subQTotWgt
      WHERE   rs.truck_id = rsav.stop_truck_id
      AND     rsav.shipment_id = subQSteelWgt.shipment_id
      AND     rsav.shipment_id = subQTotWgt.shipment_id
      AND     rs.truck_date >= pi_FirstDate
      AND     rs.truck_date <= pi_LastDate
      AND     rs.truck_status IN ('A','H','B')
      AND     EXISTS (SELECT /*+ USE_NL( roiq, ts, rsp ) */'Y'
                      FROM  reco_truckstop ts, reco_truckstop_parts rsp,
                            reco_rstx_originvqty_hist roiq
                      WHERE   rsav.shipment_id = ts.shipment_id
                      AND     rsp.part_id = roiq.inventory_item_id
                      AND     rsp.orig_subinventory_code = 'RSTX'
                      AND     roiq.cutsch_hist_id = pi_CurHistoryId)
      -- Retreive a spot for each day's proposed MANUFACTING totals           -- JNL STEEL MANUF COMMENTED
--      union
--      select  2 sort_OverallLayout,
--              calday.thedate shipment_date,
--              3 sort_DayInvQty_Ship_Mfg,
--              null sort_DelivShip_Or_Not,
--              'DAYPARTPROPOSEDMFG' rptColTypeCode,
--              1 num_child_cols,
--              null tracking_number,
--              null shipment_status,
--              null shipment_id,
--              null state,
--              null ship_stlwgt,
--              null ship_stlwgtDP,
--              null ship_totwgt
--      from  reco_rstx_calday calday -- Good:see get_date_toshowin_rpt description
--      where   calday.thedate >= pi_FirstDate
--      and     calday.thedate <= pi_LastDate
      -- Retreive a spot in collection for Final Inv Qty (last column spot)
      UNION
      SELECT  3 sort_OverallLayout,
              NULL shipment_date,
              NULL sort_DayInvQty_Ship_Mfg,
              NULL sort_DelivShip_Or_Not,
              'ENDINVTOTAL' rptColTypeCode, 
              ' ' vcFirstNegativeDateText,
              2 num_child_cols,
              NULL tracking_number,
              NULL shipment_status,
              NULL shipment_id,
              NULL STATE,
              NULL ship_stlwgt,
              NULL ship_stlwgtDP,
              NULL ship_totwgt
      FROM  dual
--      order by  sort_OverallLayout,         -- JNL COMMENT START -- V9.0
--                shipment_date,
--                sort_DayInvQty_Ship_Mfg,
--                sort_DelivShip_Or_Not,
--                tracking_number,
--                shipment_id;                -- JNL COMMENT END -- V9.0
      UNION                                   -- JNL CODE START -- V9.0
      SELECT  3 sort_OverallLayout,
              NULL shipment_date,
              NULL sort_DayInvQty_Ship_Mfg,
              NULL sort_DelivShip_Or_Not,
              'NEGATIVEINV' rptColTypeCode, 
              ' ' vcFirstNegativeDateText,
              2 num_child_cols,
              NULL tracking_number,
              NULL shipment_status,
              NULL shipment_id,
              NULL STATE,
              NULL ship_stlwgt,
              NULL ship_stlwgtDP,
              NULL ship_totwgt
      FROM  dual
      ORDER BY  sort_OverallLayout,
                shipment_date,
                sort_DayInvQty_Ship_Mfg,
                sort_DelivShip_Or_Not,
                tracking_number,
                shipment_id;                  -- JNL CODE END -- V9.0
            
                
  BEGIN
    vn_QtyColumnsInSpreadsheet := 0;
  thelocation := 'sheetstore';    
    FOR rec_ColData
    IN cur_ColData (vd_FirstDateShown,vd_LastDateShown,vn_WorkingHistId, 1, 2, 3, 4,5)
    LOOP
      oTheSheetColumnInfo.extend(1);
  thelocation := 'sheetstore'||rec_ColData.shipment_id;   
      
      oTheSheetColumnInfo(oTheSheetColumnInfo.count).rptColTypeCode
              := rec_ColData.rptColTypeCode;
      oTheSheetColumnInfo(oTheSheetColumnInfo.count).num_child_cols
              := rec_ColData.num_child_cols;
      oTheSheetColumnInfo(oTheSheetColumnInfo.count).shipment_date
              := rec_ColData.shipment_date;
      oTheSheetColumnInfo(oTheSheetColumnInfo.count).tracking_number
              := rec_ColData.tracking_number;
      oTheSheetColumnInfo(oTheSheetColumnInfo.count).shipment_status
              := rec_ColData.shipment_status;
      oTheSheetColumnInfo(oTheSheetColumnInfo.count).shipment_id
              := rec_ColData.shipment_id;
      oTheSheetColumnInfo(oTheSheetColumnInfo.count).STATE
              := rec_ColData.state;
      oTheSheetColumnInfo(oTheSheetColumnInfo.count).daystrt_npb_tonn
              := NULL;
      oTheSheetColumnInfo(oTheSheetColumnInfo.count).daystrt_spb_tonn
              := NULL;
      oTheSheetColumnInfo(oTheSheetColumnInfo.count).daystrt_spg_tonn
              := NULL;
      oTheSheetColumnInfo(oTheSheetColumnInfo.count).daystrt_dpb_tonn
              := NULL;
      oTheSheetColumnInfo(oTheSheetColumnInfo.count).daystrt_dpg_tonn
              := NULL;
      oTheSheetColumnInfo(oTheSheetColumnInfo.count).daystrt506_npb_tonn
              := NULL;
      oTheSheetColumnInfo(oTheSheetColumnInfo.count).daystrt506_spb_tonn
              := NULL;
      oTheSheetColumnInfo(oTheSheetColumnInfo.count).daystrt506_spg_tonn
              := NULL;
      oTheSheetColumnInfo(oTheSheetColumnInfo.count).daystrt506_dpb_tonn
              := NULL;
      oTheSheetColumnInfo(oTheSheetColumnInfo.count).daystrt506_dpg_tonn        
              := NULL;
      oTheSheetColumnInfo(oTheSheetColumnInfo.count).vcFirstNegativeDateText
              := rec_ColData.vcFirstNegativeDateText;
      oTheSheetColumnInfo(oTheSheetColumnInfo.count).ship_stlwgt
              := rec_ColData.ship_stlwgt;
      oTheSheetColumnInfo(oTheSheetColumnInfo.count).ship_stlwgtDP
              := rec_ColData.ship_stlwgtDP;
      oTheSheetColumnInfo(oTheSheetColumnInfo.count).ship_totwgt
              := rec_ColData.ship_totwgt;
      oTheSheetColumnInfo(oTheSheetColumnInfo.count).day_manuf_spb_tonn
              := NULL;
      oTheSheetColumnInfo(oTheSheetColumnInfo.count).day_manuf_dpb_tonn
              := NULL;
      
      vn_QtyColumnsInSpreadsheet :=
        vn_QtyColumnsInSpreadsheet + rec_ColData.num_child_cols;
  END LOOP;
    
  END;
    thelocation := 'endstore';
-- ************************************************************************************* JNL TEST  END  
  
  DECLARE
    -- Selects all the numbers we will need for inventory-tonnage
    -- totals on a given day.
    -- Note#1 - When in doubt, assume SinglePunch is root table (over galv)
    -- Note#2 - When in doubt, assume Galv is root table (over black/nopunch)
    CURSOR cur_TonnagesForRptDate (pi_DesiredDay IN date, 
                                   pi_sortOrder IN NUMBER, pi_sortOrder2 IN NUMBER)
    IS
      SELECT  rptGrp1Parts.n_originvqty npb_originvqty,
              msibGrp1NoPun.unit_weight npb_unit_weight,
              msibGrp1NoPun.weight_uom_code npb_weight_uom_code,
              rptGrp1Parts.b_originvqty spb_originvqty,
              msibGrp1Black.unit_weight spb_unit_weight,
              msibGrp1Black.weight_uom_code spb_weight_uom_code,
              rptGrp1Parts.g_originvqty spg_originvqty,
              msibGrp1Galv.unit_weight spg_unit_weight,
              msibGrp1Galv.weight_uom_code spg_weight_uom_code,
              
              NVL(rptGrp2Parts.b_originvqty,0) dpb_originvqty,
              NVL(msibGrp2Black.unit_weight,0) dpb_unit_weight,
              NVL(msibGrp2Black.weight_uom_code,'LB') dpb_weight_uom_code,
              NVL(rptGrp2Parts.g_originvqty,0) dpg_originvqty,
              NVL(msibGrp2Galv.unit_weight,0) dpg_unit_weight,
              NVL(msibGrp2Galv.weight_uom_code,'LB') dpg_weight_uom_code,
              
              NVL(subQGrp1BlackShippedQty.totalPcs,0) spb_ship_cumm_qty,
              NVL(subQGrp1GalvShippedQty.totalPcs,0) spg_ship_cumm_qty,
              NVL(subQGrp1BlackMfgDailyQty.totalPcs,0) spb_newpun_today_qty,
              NVL(subQGrp1BlackMfgCummQty.totalPcs,0) spb_newpun_cumm_qty,
                            
              NVL(subQGrp2BlackShippedQty.totalPcs,0) dpb_ship_cumm_qty,
              NVL(subQGrp2GalvShippedQty.totalPcs,0) dpg_ship_cumm_qty,
              NVL(subQGrp2BlackMfgDailyQty.totalPcs,0) dpb_newpun_today_qty,
              NVL(subQGrp2BlackMfgCummQty.totalPcs,0) dpb_newpun_cumm_qty
                            
      FROM  reco_rstx_tmpshpcalparts rptGrp1Parts,
            reco_rstx_tmpshpcalparts rptGrp2Parts,
            apps.mtl_system_items_b_kfv msibGrp1NoPun,
            apps.mtl_system_items_b_kfv msibGrp1Black,
            apps.mtl_system_items_b_kfv msibGrp1Galv,
            apps.mtl_system_items_b_kfv msibGrp2Black,
            apps.mtl_system_items_b_kfv msibGrp2Galv,
        
            (
              SELECT  subparts.b_partid,
                      SUM(subrsp.quantity) totalPcs
              FROM  reco_truck subrs,
                    reco_truckstop_parts_v subrsp,
                    reco_rstx_tmpshpcalparts subparts
              WHERE   subrsp.stop_truck_id = subrs.truck_id
              AND     subrsp.part_id = subparts.b_partid
              AND     subrs.truck_date >= vd_FirstDateShown
              AND     subrs.truck_date < pi_DesiredDay
              AND     subrs.truck_status
                        -- Note: Rpt shows deliviered for today and future
                        IN ('A','H','B','D')
              AND     subrsp.orig_subinventory_code = 'RSTX'
              AND     subparts.sortorder IN (pi_sortOrder, pi_sortOrder2)
              GROUP BY  subparts.b_partid
            ) subQGrp1BlackShippedQty,

            (
              SELECT  subparts.g_partid,
                      SUM(subrsp.quantity) totalPcs
              FROM  reco_truck subrs,
                    reco_truckstop_parts_v subrsp,
                    reco_rstx_tmpshpcalparts subparts
              WHERE   subrsp.stop_truck_id = subrs.truck_id
              AND     subrsp.part_id = subparts.g_partid
              AND     subrs.truck_date >= vd_FirstDateShown
              AND     subrs.truck_date < pi_DesiredDay
              AND     subrs.truck_status
                        -- Note: Rpt shows deliviered for today and future
                        IN ('A','H','B','D')
              AND     subrsp.orig_subinventory_code = 'RSTX'
              AND     subparts.sortorder IN (pi_sortOrder, pi_sortOrder2)
              GROUP BY  subparts.g_partid
            ) subQGrp1GalvShippedQty,

            (
              SELECT  subparts.b_partid,
                      SUM(punrunhist.qty_bars_processed) totalPcs
              FROM  reco_rstx_calday calday,
                              -- Good:get_date_toshowin_rpt description
                    reco_rstx_punrun_hist punrunhist,
                    (
                      SELECT DISTINCT
                              subasg.punrun_id,
                              subreq.reqlength,
                              subreq.reqtype,
                              subreq.reqpunch
                              --NOTE: We do not care about PunchSch coating
                              --      because for this report we label all
                              --      punching results as black pieces
                      FROM  reco_rstx_punrun_hist subrun,
                            reco_rstx_punreq_hist subreq,
                            reco_rstx_punasg_hist subasg
                      WHERE   subrun.punrun_id = subasg.punrun_id
                      AND     subasg.punreq_id = subreq.punreq_id
                      AND     subrun.cutsch_hist_id = vn_WorkingHistId
                      AND     subasg.cutsch_hist_id = vn_WorkingHistId
                      AND     subreq.cutsch_hist_id = vn_WorkingHistId
                    ) subQPartData,
                    reco_rstx_tmpshpcalparts subparts
              WHERE   calday.thedate = pi_DesiredDay
              AND     calday.calday_id = punrunhist.calday_id
              AND     punrunhist.cutsch_hist_id = vn_WorkingHistId
              AND     punrunhist.punrun_id = subQPartData.punrun_id
              AND     subQPartData.reqlength = subparts.b_partnumlen
              AND     subQPartData.reqtype = subparts.b_parttype
              AND     subQPartData.reqpunch = subparts.b_partpunch
              AND     subparts.sortorder IN (pi_sortOrder, pi_sortOrder2)
              GROUP BY  subparts.b_partid
            ) subQGrp1BlackMfgDailyQty,

            (
              SELECT  subparts.b_partid,
                      SUM(punrunhist.qty_bars_processed) totalPcs
              FROM  reco_rstx_calday calday,
                              -- Good:get_date_toshowin_rpt description
                    reco_rstx_punrun_hist punrunhist,
                    (
                      SELECT DISTINCT
                              subasg.punrun_id,
                              subreq.reqlength,
                              subreq.reqtype,
                              subreq.reqpunch
                              --NOTE: We do not care about PunchSch coating
                              --      because for this report we label all
                              --      punching results as black pieces
                      FROM  reco_rstx_punrun_hist subrun,
                            reco_rstx_punreq_hist subreq,
                            reco_rstx_punasg_hist subasg
                      WHERE   subrun.punrun_id = subasg.punrun_id
                      AND     subasg.punreq_id = subreq.punreq_id
                      AND     subrun.cutsch_hist_id = vn_WorkingHistId
                      AND     subasg.cutsch_hist_id = vn_WorkingHistId
                      AND     subreq.cutsch_hist_id = vn_WorkingHistId
                    ) subQPartData,
                    reco_rstx_tmpshpcalparts subparts
              WHERE   calday.thedate >= vd_FirstDateShown
              AND     calday.thedate < pi_DesiredDay
              AND     calday.calday_id = punrunhist.calday_id
              AND     punrunhist.cutsch_hist_id = vn_WorkingHistId
              AND     punrunhist.punrun_id = subQPartData.punrun_id
              AND     subQPartData.reqlength = subparts.b_partnumlen
              AND     subQPartData.reqtype = subparts.b_parttype
              AND     subQPartData.reqpunch = subparts.b_partpunch
              AND     subparts.sortorder IN (pi_sortOrder, pi_sortOrder2)
              GROUP BY  subparts.b_partid
            ) subQGrp1BlackMfgCummQty,

            (
              SELECT  subparts.b_partid,
                      SUM(subrsp.quantity) totalPcs
              FROM  reco_truck subrs,
                    reco_truckstop_parts_v subrsp,
                    reco_rstx_tmpshpcalparts subparts
              WHERE   subrsp.stop_truck_id = subrs.truck_id
              AND     subrsp.part_id = subparts.b_partid
              AND     subrs.truck_date >= vd_FirstDateShown
              AND     subrs.truck_date < pi_DesiredDay
              AND     subrs.truck_status
                        -- Note: Rpt shows deliviered for today and future
                        IN ('A','H','B','D')
              AND     subrsp.orig_subinventory_code = 'RSTX'
              AND     subparts.sortorder IN (pi_sortOrder, pi_sortOrder2)
              GROUP BY  subparts.b_partid
            ) subQGrp2BlackShippedQty,

            (
              SELECT  subparts.g_partid,
                      SUM(subrsp.quantity) totalPcs
              FROM  reco_truck subrs,
                    reco_truckstop_parts_v subrsp,
                    reco_rstx_tmpshpcalparts subparts
              WHERE   subrsp.stop_truck_id = subrs.truck_id
              AND     subrsp.part_id = subparts.g_partid
              AND     subrs.truck_date >= vd_FirstDateShown
              AND     subrs.truck_date < pi_DesiredDay
              AND     subrs.truck_status
                        -- Note: Rpt shows deliviered for today and future
                        IN ('A','H','B','D')
              AND     subrsp.orig_subinventory_code = 'RSTX'
              AND     subparts.sortorder IN (pi_sortOrder, pi_sortOrder2)
              GROUP BY  subparts.g_partid
            ) subQGrp2GalvShippedQty,

            (
              SELECT  subparts.b_partid,
                      SUM(punrunhist.qty_bars_processed) totalPcs
              FROM  reco_rstx_calday calday,
                              -- Good:get_date_toshowin_rpt description
                    reco_rstx_punrun_hist punrunhist,
                    (
                      SELECT DISTINCT
                              subasg.punrun_id,
                              subreq.reqlength,
                              subreq.reqtype,
                              subreq.reqpunch
                              --NOTE: We do not care about PunchSch coating
                              --      because for this report we label all
                              --      punching results as black pieces
                      FROM  reco_rstx_punrun_hist subrun,
                            reco_rstx_punreq_hist subreq,
                            reco_rstx_punasg_hist subasg
                      WHERE   subrun.punrun_id = subasg.punrun_id
                      AND     subasg.punreq_id = subreq.punreq_id
                      AND     subrun.cutsch_hist_id = vn_WorkingHistId
                      AND     subasg.cutsch_hist_id = vn_WorkingHistId
                      AND     subreq.cutsch_hist_id = vn_WorkingHistId
                    ) subQPartData,
                    reco_rstx_tmpshpcalparts subparts
              WHERE   calday.thedate = pi_DesiredDay
              AND     calday.calday_id = punrunhist.calday_id
              AND     punrunhist.cutsch_hist_id = vn_WorkingHistId
              AND     punrunhist.punrun_id = subQPartData.punrun_id
              AND     subQPartData.reqlength = subparts.b_partnumlen
              AND     subQPartData.reqtype = subparts.b_parttype
              AND     subQPartData.reqpunch = subparts.b_partpunch
              AND     subparts.sortorder IN (pi_sortOrder, pi_sortOrder2)
              GROUP BY  subparts.b_partid
            ) subQGrp2BlackMfgDailyQty,

            (
              SELECT  subparts.b_partid,
                      SUM(punrunhist.qty_bars_processed) totalPcs
              FROM  reco_rstx_calday  calday,
                              -- Good:get_date_toshowin_rpt description
                    reco_rstx_punrun_hist punrunhist,
                    (
                      SELECT DISTINCT
                              subasg.punrun_id,
                              subreq.reqlength,
                              subreq.reqtype,
                              subreq.reqpunch
                              --NOTE: We do not care about PunchSch coating
                              --      because for this report we label all
                              --      punching results as black pieces
                      FROM  reco_rstx_punrun_hist subrun,
                            reco_rstx_punreq_hist subreq,
                            reco_rstx_punasg_hist subasg
                      WHERE   subrun.punrun_id = subasg.punrun_id
                      AND     subasg.punreq_id = subreq.punreq_id
                      AND     subrun.cutsch_hist_id = vn_WorkingHistId
                      AND     subasg.cutsch_hist_id = vn_WorkingHistId
                      AND     subreq.cutsch_hist_id = vn_WorkingHistId
                    ) subQPartData,
                    reco_rstx_tmpshpcalparts subparts
              WHERE   calday.thedate >= vd_FirstDateShown
              AND     calday.thedate < pi_DesiredDay
              AND     calday.calday_id = punrunhist.calday_id
              AND     punrunhist.cutsch_hist_id = vn_WorkingHistId
              AND     punrunhist.punrun_id = subQPartData.punrun_id
              AND     subQPartData.reqlength = subparts.b_partnumlen
              AND     subQPartData.reqtype = subparts.b_parttype
              AND     subQPartData.reqpunch = subparts.b_partpunch
              AND     subparts.sortorder IN (pi_sortOrder, pi_sortOrder2)
              GROUP BY  subparts.b_partid
            ) subQGrp2BlackMfgCummQty    
            
      WHERE   rptGrp1Parts.sortorder = pi_sortOrder
      AND     rptGrp1Parts.n_partid = rptGrp2Parts.n_partid (+)
      AND     rptGrp2Parts.sortorder (+) = pi_sortOrder2
      AND     rptGrp1Parts.n_partid = msibGrp1NoPun.inventory_item_id (+)
      and   msibgrp1nopun.organization_id(+) = 0
      AND     rptGrp1Parts.b_partid = msibGrp1Black.inventory_item_id (+)
      and   msibgrp1black.organization_id(+) = 0
      AND     rptGrp1Parts.g_partid = msibGrp1Galv.inventory_item_id (+)
      and   msibgrp1galv.organization_id(+) = 0
      AND     rptGrp2Parts.b_partid = msibGrp2Black.inventory_item_id (+)
      and   msibgrp2black.organization_id(+) = 0
      AND     rptGrp2Parts.g_partid = msibGrp2Galv.inventory_item_id (+)
      and   msibgrp2galv.organization_id(+) = 0
      AND     rptGrp1Parts.b_partid = subQGrp1BlackShippedQty.b_partid (+)
      AND     rptGrp1Parts.g_partid = subQGrp1GalvShippedQty.g_partid (+)
      AND     rptGrp1Parts.b_partid = subQGrp1BlackMfgDailyQty.b_partid (+)
      AND     rptGrp1Parts.b_partid = subQGrp1BlackMfgCummQty.b_partid (+)
      AND     rptGrp2Parts.b_partid = subQGrp2BlackShippedQty.b_partid (+)
      AND     rptGrp2Parts.g_partid = subQGrp2GalvShippedQty.g_partid (+)
      AND     rptGrp2Parts.b_partid = subQGrp2BlackMfgDailyQty.b_partid (+)
      AND     rptGrp2Parts.b_partid = subQGrp2BlackMfgCummQty.b_partid (+);
    
    vn_CachedSPBMfgTot number;
    vn_CachedDPBMfgTot number;
    vn_CachedSPBMfgTot506 number;
    vn_CachedDPBMfgTot506 number;
    
    --vb_FirstNegativeDateSet BOOLEAN;
  BEGIN
    
   -- vb_FirstNegativeDateSet := false;
  thelocation := 'dailyquery';    
    IF oTheSheetColumnInfo.count > 0
    THEN
      
      nCtrSheetColumnInfo := 1;
      
      LOOP
        
        IF oTheSheetColumnInfo(nCtrSheetColumnInfo).rptColTypeCode
                = 'DAILYPARTINV'
        THEN
          oTheSheetColumnInfo(nCtrSheetColumnInfo).daystrt_npb_tonn := 0;
          oTheSheetColumnInfo(nCtrSheetColumnInfo).daystrt_spb_tonn := 0;
          oTheSheetColumnInfo(nCtrSheetColumnInfo).daystrt_spg_tonn := 0;
          oTheSheetColumnInfo(nCtrSheetColumnInfo).daystrt_dpb_tonn := 0;
          oTheSheetColumnInfo(nCtrSheetColumnInfo).daystrt_dpg_tonn := 0;
          vn_CachedSPBMfgTot := 0;
          vn_CachedDPBMfgTot := 0;
--          vb_FirstNegativeDateSet := false;
          
          FOR rec_TonnagesForRptDate
          IN cur_TonnagesForRptDate(
                  oTheSheetColumnInfo(nCtrSheetColumnInfo).shipment_date, 1, 2)
          LOOP
            oTheSheetColumnInfo(nCtrSheetColumnInfo).daystrt_npb_tonn :=
                oTheSheetColumnInfo(nCtrSheetColumnInfo).daystrt_npb_tonn
                +
                (
                  reco_estimation.convert_to(
                        rec_TonnagesForRptDate.npb_unit_weight,
                        rec_TonnagesForRptDate.npb_weight_uom_code,
                        'TO')
                  *
                  (
                    (
                      rec_TonnagesForRptDate.npb_originvqty - 0 + 0
                    )
                  )
                );
            
            oTheSheetColumnInfo(nCtrSheetColumnInfo).daystrt_spb_tonn :=
                oTheSheetColumnInfo(nCtrSheetColumnInfo).daystrt_spb_tonn
                +
                (
                  reco_estimation.convert_to(
                        rec_TonnagesForRptDate.spb_unit_weight,
                        rec_TonnagesForRptDate.spb_weight_uom_code,
                        'TO')
                  *
                  (
                    (
                      rec_TonnagesForRptDate.spb_originvqty
                      -
                      rec_TonnagesForRptDate.spb_ship_cumm_qty
                    )
                    +
                    rec_TonnagesForRptDate.spb_newpun_cumm_qty
                  )
                );
                           
            oTheSheetColumnInfo(nCtrSheetColumnInfo).daystrt_spg_tonn :=
                oTheSheetColumnInfo(nCtrSheetColumnInfo).daystrt_spg_tonn
                +
                (
                  reco_estimation.convert_to(
                        rec_TonnagesForRptDate.spg_unit_weight,
                        rec_TonnagesForRptDate.spg_weight_uom_code,
                        'TO')
                  *
                  (
                    (
                      rec_TonnagesForRptDate.spg_originvqty
                      -
                      rec_TonnagesForRptDate.spg_ship_cumm_qty
                    )
                    +
                    0
                  )
                );
                
            -- -------------------------------------------------------------------------------------------
--            if ( oTheSheetColumnInfo(nCtrSheetColumnInfo).daystrt_spg_tonn < 0 AND vb_FirstNegativeDateSet = false  )
--              then 
--              oTheSheetColumnInfo(nCtrSheetColumnInfo).vcFirstNegativeDateText := 'TEST';
--              --((to_char(oTheSheetColumnInfo(nCtrSheetColumnInfo).shipment_date,'DY DD-MON')));
--              vb_FirstNegativeDateSet := true;
--            end if;
--                   
--            if ( oTheSheetColumnInfo(nCtrSheetColumnInfo).daystrt_spb_tonn < 0 AND vb_FirstNegativeDateSet = false )
--              then 
--              oTheSheetColumnInfo(nCtrSheetColumnInfo).vcFirstNegativeDateText := 'TEST';
--              --((to_char(oTheSheetColumnInfo(nCtrSheetColumnInfo).shipment_date,'DY DD-MON')));
--              vb_FirstNegativeDateSet := true;
--            end if;              
            -- --------------------------------------------------------------------------------------------
            
            oTheSheetColumnInfo(nCtrSheetColumnInfo).daystrt_dpb_tonn :=
                oTheSheetColumnInfo(nCtrSheetColumnInfo).daystrt_dpb_tonn
                +
                (
                  reco_estimation.convert_to(
                        rec_TonnagesForRptDate.dpb_unit_weight,
                        rec_TonnagesForRptDate.dpb_weight_uom_code,
                        'TO')
                  *
                  (
                    (
                      rec_TonnagesForRptDate.dpb_originvqty
                      -
                      rec_TonnagesForRptDate.dpb_ship_cumm_qty
                    )
                    +
                    rec_TonnagesForRptDate.dpb_newpun_cumm_qty
                  )
                );
            
            oTheSheetColumnInfo(nCtrSheetColumnInfo).daystrt_dpg_tonn :=
                oTheSheetColumnInfo(nCtrSheetColumnInfo).daystrt_dpg_tonn
                +
                (
                  reco_estimation.convert_to(
                        rec_TonnagesForRptDate.dpg_unit_weight,
                        rec_TonnagesForRptDate.dpg_weight_uom_code,
                        'TO')
                  *
                  (
                    (
                      rec_TonnagesForRptDate.dpg_originvqty
                      -
                      rec_TonnagesForRptDate.dpg_ship_cumm_qty
                    )
                    +
                    0
                  )
                );
          END LOOP;
        ELSIF oTheSheetColumnInfo(nCtrSheetColumnInfo).rptColTypeCode
                = 'ENDINVTOTAL'
        THEN
          oTheSheetColumnInfo(nCtrSheetColumnInfo).daystrt_npb_tonn := 0;
          oTheSheetColumnInfo(nCtrSheetColumnInfo).daystrt_spb_tonn := 0;
          oTheSheetColumnInfo(nCtrSheetColumnInfo).daystrt_spg_tonn := 0;
          oTheSheetColumnInfo(nCtrSheetColumnInfo).daystrt_dpb_tonn := 0;
          oTheSheetColumnInfo(nCtrSheetColumnInfo).daystrt_dpg_tonn := 0;
          vn_CachedSPBMfgTot := 0;
          vn_CachedDPBMfgTot := 0;
          
          FOR rec_TonnagesForRptDate
          IN cur_TonnagesForRptDate( (vd_LastDateShown + 1), 1, 2)
          LOOP
            oTheSheetColumnInfo(nCtrSheetColumnInfo).daystrt_npb_tonn :=
                oTheSheetColumnInfo(nCtrSheetColumnInfo).daystrt_npb_tonn
                +
                (
                  reco_estimation.convert_to(
                        rec_TonnagesForRptDate.npb_unit_weight,
                        rec_TonnagesForRptDate.npb_weight_uom_code,
                        'TO')
                  *
                  (
                    (
                      rec_TonnagesForRptDate.npb_originvqty - 0 + 0
                    )
                  )
                );
            
            oTheSheetColumnInfo(nCtrSheetColumnInfo).daystrt_spb_tonn :=
                oTheSheetColumnInfo(nCtrSheetColumnInfo).daystrt_spb_tonn
                +
                (
                  reco_estimation.convert_to(
                        rec_TonnagesForRptDate.spb_unit_weight,
                        rec_TonnagesForRptDate.spb_weight_uom_code,
                        'TO')
                  *
                  (
                    (
                      rec_TonnagesForRptDate.spb_originvqty
                      -
                      rec_TonnagesForRptDate.spb_ship_cumm_qty
                    )
                    +
                    rec_TonnagesForRptDate.spb_newpun_cumm_qty
                  )
                );
            
            oTheSheetColumnInfo(nCtrSheetColumnInfo).daystrt_spg_tonn :=
                oTheSheetColumnInfo(nCtrSheetColumnInfo).daystrt_spg_tonn
                +
                (
                  reco_estimation.convert_to(
                        rec_TonnagesForRptDate.spg_unit_weight,
                        rec_TonnagesForRptDate.spg_weight_uom_code,
                        'TO')
                  *
                  (
                    (
                      rec_TonnagesForRptDate.spg_originvqty
                      -
                      rec_TonnagesForRptDate.spg_ship_cumm_qty
                    )
                    +
                    0
                  )
                );
            
            oTheSheetColumnInfo(nCtrSheetColumnInfo).daystrt_dpb_tonn :=
                oTheSheetColumnInfo(nCtrSheetColumnInfo).daystrt_dpb_tonn
                +
                (
                  reco_estimation.convert_to(
                        rec_TonnagesForRptDate.dpb_unit_weight,
                        rec_TonnagesForRptDate.dpb_weight_uom_code,
                        'TO')
                  *
                  (
                    (
                      rec_TonnagesForRptDate.dpb_originvqty
                      -
                      rec_TonnagesForRptDate.dpb_ship_cumm_qty
                    )
                    +
                    rec_TonnagesForRptDate.dpb_newpun_cumm_qty
                  )
                );
            
            oTheSheetColumnInfo(nCtrSheetColumnInfo).daystrt_dpg_tonn :=
                oTheSheetColumnInfo(nCtrSheetColumnInfo).daystrt_dpg_tonn
                +
                (
                  reco_estimation.convert_to(
                        rec_TonnagesForRptDate.dpg_unit_weight,
                        rec_TonnagesForRptDate.dpg_weight_uom_code,
                        'TO')
                  *
                  (
                    (
                      rec_TonnagesForRptDate.dpg_originvqty
                      -
                      rec_TonnagesForRptDate.dpg_ship_cumm_qty
                    )
                    +
                    0
                  )
                );
            
          END LOOP;
        END IF;

        IF nCtrSheetColumnInfo = oTheSheetColumnInfo.count
        THEN exit;
        END IF;
        
        nCtrSheetColumnInfo := nCtrSheetColumnInfo + 1;
      END LOOP;
    END IF;
      thelocation := 'enddaily';
-- ********************************************************************************** JNL 6.0 START
-- **********************************************************************************
    IF oTheSheetColumnInfo.count > 0
        THEN
          
          nCtrSheetColumnInfo := 1;
          
          LOOP
            
            IF oTheSheetColumnInfo(nCtrSheetColumnInfo).rptColTypeCode
                    = 'DAILYPARTINV'
            THEN
              oTheSheetColumnInfo(nCtrSheetColumnInfo).daystrt506_npb_tonn := 0;
              oTheSheetColumnInfo(nCtrSheetColumnInfo).daystrt506_spb_tonn := 0;
              oTheSheetColumnInfo(nCtrSheetColumnInfo).daystrt506_spg_tonn := 0;
              oTheSheetColumnInfo(nCtrSheetColumnInfo).daystrt506_dpb_tonn := 0;
              oTheSheetColumnInfo(nCtrSheetColumnInfo).daystrt506_dpg_tonn := 0;
              oTheSheetColumnInfo(nCtrSheetColumnInfo).vcFirstNegativeDateText := '';
              vn_CachedSPBMfgTot506 := 0;
              vn_CachedDPBMfgTot506 := 0;
              
              FOR rec_TonnagesForRptDate
              IN cur_TonnagesForRptDate(
                      oTheSheetColumnInfo(nCtrSheetColumnInfo).shipment_date, 3, 4)
              LOOP
                oTheSheetColumnInfo(nCtrSheetColumnInfo).daystrt506_npb_tonn :=
                    oTheSheetColumnInfo(nCtrSheetColumnInfo).daystrt506_npb_tonn
                    +
                    (
                      reco_estimation.convert_to(
                            rec_TonnagesForRptDate.npb_unit_weight,
                            rec_TonnagesForRptDate.npb_weight_uom_code,
                            'TO')
                      *
                      (
                        (
                          NVL(rec_TonnagesForRptDate.npb_originvqty - 0 + 0,0)
                        )
                      )
                    );
                
                oTheSheetColumnInfo(nCtrSheetColumnInfo).daystrt506_spb_tonn :=
                    oTheSheetColumnInfo(nCtrSheetColumnInfo).daystrt506_spb_tonn
                    +
                    (
                      reco_estimation.convert_to(
                            rec_TonnagesForRptDate.spb_unit_weight,
                            rec_TonnagesForRptDate.spb_weight_uom_code,
                            'TO')
                      *
                      (
                        (
                          rec_TonnagesForRptDate.spb_originvqty
                          -
                          rec_TonnagesForRptDate.spb_ship_cumm_qty
                        )
                        +
                        rec_TonnagesForRptDate.spb_newpun_cumm_qty
                      )
                    );
                
                oTheSheetColumnInfo(nCtrSheetColumnInfo).daystrt506_spg_tonn :=
                    oTheSheetColumnInfo(nCtrSheetColumnInfo).daystrt506_spg_tonn
                    +
                    (
                      reco_estimation.convert_to(
                            rec_TonnagesForRptDate.spg_unit_weight,
                            rec_TonnagesForRptDate.spg_weight_uom_code,
                            'TO')
                      *
                      (
                        (
                          rec_TonnagesForRptDate.spg_originvqty
                          -
                          rec_TonnagesForRptDate.spg_ship_cumm_qty
                        )
                        +
                        0
                      )
                    );
                
                oTheSheetColumnInfo(nCtrSheetColumnInfo).daystrt506_dpb_tonn :=
                    oTheSheetColumnInfo(nCtrSheetColumnInfo).daystrt506_dpb_tonn
                    +
                    (
                      reco_estimation.convert_to(
                            rec_TonnagesForRptDate.dpb_unit_weight,
                            rec_TonnagesForRptDate.dpb_weight_uom_code,
                            'TO')
                      *
                      (
                        (
                          rec_TonnagesForRptDate.dpb_originvqty
                          -
                          rec_TonnagesForRptDate.dpb_ship_cumm_qty
                        )
                        +
                        rec_TonnagesForRptDate.dpb_newpun_cumm_qty
                      )
                    );
                
                oTheSheetColumnInfo(nCtrSheetColumnInfo).daystrt506_dpg_tonn :=
                    oTheSheetColumnInfo(nCtrSheetColumnInfo).daystrt506_dpg_tonn
                    +
                    (
                      reco_estimation.convert_to(
                            rec_TonnagesForRptDate.dpg_unit_weight,
                            rec_TonnagesForRptDate.dpg_weight_uom_code,
                            'TO')
                      *
                      (
                        (
                          rec_TonnagesForRptDate.dpg_originvqty
                          -
                          rec_TonnagesForRptDate.dpg_ship_cumm_qty
                        )
                        +
                        0
                      )
                    );
              END LOOP;
            ELSIF oTheSheetColumnInfo(nCtrSheetColumnInfo).rptColTypeCode
                    = 'ENDINVTOTAL'
            THEN
              oTheSheetColumnInfo(nCtrSheetColumnInfo).daystrt506_npb_tonn := 0;
              oTheSheetColumnInfo(nCtrSheetColumnInfo).daystrt506_spb_tonn := 0;
              oTheSheetColumnInfo(nCtrSheetColumnInfo).daystrt506_spg_tonn := 0;
              oTheSheetColumnInfo(nCtrSheetColumnInfo).daystrt506_dpb_tonn := 0;
              oTheSheetColumnInfo(nCtrSheetColumnInfo).daystrt506_dpg_tonn := 0;
              vn_CachedSPBMfgTot506 := 0;
              vn_CachedDPBMfgTot506 := 0;
              
              FOR rec_TonnagesForRptDate
              IN cur_TonnagesForRptDate( (vd_LastDateShown + 1), 3, 4)
              LOOP
                oTheSheetColumnInfo(nCtrSheetColumnInfo).daystrt506_npb_tonn :=
                    oTheSheetColumnInfo(nCtrSheetColumnInfo).daystrt506_npb_tonn
                    +
                    (
                      reco_estimation.convert_to(
                            rec_TonnagesForRptDate.npb_unit_weight,
                            rec_TonnagesForRptDate.npb_weight_uom_code,
                            'TO')
                      *
                      (
                        (
                          rec_TonnagesForRptDate.npb_originvqty - 0 + 0
                        )
                      )
                    );
                
                oTheSheetColumnInfo(nCtrSheetColumnInfo).daystrt506_spb_tonn :=
                    oTheSheetColumnInfo(nCtrSheetColumnInfo).daystrt506_spb_tonn
                    +
                    (
                      reco_estimation.convert_to(
                            rec_TonnagesForRptDate.spb_unit_weight,
                            rec_TonnagesForRptDate.spb_weight_uom_code,
                            'TO')
                      *
                      (
                        (
                          rec_TonnagesForRptDate.spb_originvqty
                          -
                          rec_TonnagesForRptDate.spb_ship_cumm_qty
                        )
                        +
                        rec_TonnagesForRptDate.spb_newpun_cumm_qty
                      )
                    );
                
                oTheSheetColumnInfo(nCtrSheetColumnInfo).daystrt506_spg_tonn :=
                    oTheSheetColumnInfo(nCtrSheetColumnInfo).daystrt506_spg_tonn
                    +
                    (
                      reco_estimation.convert_to(
                            rec_TonnagesForRptDate.spg_unit_weight,
                            rec_TonnagesForRptDate.spg_weight_uom_code,
                            'TO')
                      *
                      (
                        (
                          rec_TonnagesForRptDate.spg_originvqty
                          -
                          rec_TonnagesForRptDate.spg_ship_cumm_qty
                        )
                        +
                        0
                      )
                    );
                
                oTheSheetColumnInfo(nCtrSheetColumnInfo).daystrt506_dpb_tonn :=
                    oTheSheetColumnInfo(nCtrSheetColumnInfo).daystrt506_dpb_tonn
                    +
                    (
                      reco_estimation.convert_to(
                            rec_TonnagesForRptDate.dpb_unit_weight,
                            rec_TonnagesForRptDate.dpb_weight_uom_code,
                            'TO')
                      *
                      (
                        (
                          rec_TonnagesForRptDate.dpb_originvqty
                          -
                          rec_TonnagesForRptDate.dpb_ship_cumm_qty
                        )
                        +
                        rec_TonnagesForRptDate.dpb_newpun_cumm_qty
                      )
                    );
                
                oTheSheetColumnInfo(nCtrSheetColumnInfo).daystrt506_dpg_tonn :=
                    oTheSheetColumnInfo(nCtrSheetColumnInfo).daystrt506_dpg_tonn
                    +
                    (
                      reco_estimation.convert_to(
                            rec_TonnagesForRptDate.dpg_unit_weight,
                            rec_TonnagesForRptDate.dpg_weight_uom_code,
                            'TO')
                      *
                      (
                        (
                          rec_TonnagesForRptDate.dpg_originvqty
                          -
                          rec_TonnagesForRptDate.dpg_ship_cumm_qty
                        )
                        +
                        0
                      )
                    );
              END LOOP;
            END IF;
            
            IF nCtrSheetColumnInfo = oTheSheetColumnInfo.count
            THEN exit;
            END IF;
            
            nCtrSheetColumnInfo := nCtrSheetColumnInfo + 1;
          END LOOP;
        END IF;
          thelocation := 'enddaily2';
-- **********************************************************************************
-- ********************************************************************************** JNL 6.0 END
  END;
  
  ---
  -- Prepare spreadsheet
  ---

  reco_web_functions.reset_sheet;
  thelocation := 'reset';
  reco_web_functions.table_attr := 'border="1" frame="border" rules="all"';
  thelocation := 'attr';
--  reco_web_functions.open_spreadsheet;  --('Shipping_Calendar'); 
  reco_web_functions.open_spreadsheet('NODATE:reco_steel_shipments_report'); --Added by RS on 03/04/2026.
  thelocation := 'open';
  ---
  -- Print notification if we couldn't actually access start-of-day info
  ---
  
  IF vc_WorkingHistUser != 'NIGHTLY AUTO REFRESH'
  THEN
    reco_web_functions.clear_headers;
    reco_web_functions.col_span := 16;
    reco_web_functions.cell_attr := '';
    reco_web_functions.add_header_column(
      'Warning: Could not access Morning INV numbers. '||
      'The shipping is accurate, but the displayed inventory numbers '||
      'may not match the Morning INV quantities');
    reco_web_functions.print_header;
  END IF;
  
  ---
  -- Header - Print First Row - Date
  ---
  thelocation := 'clear';
  reco_web_functions.clear_headers;
  
  reco_web_functions.col_span := oTheSheetColumnInfo(1).num_child_cols;
  --reco_web_functions.col_span := oTheSheetColumnInfoSP(1).num_child_cols;
  --reco_web_functions.col_span := oTheSheetColumnInfoDP(1).num_child_cols;
  reco_web_functions.cell_attr := '';
  reco_web_functions.add_header_column('Steel Ship');
  thelocation := 'begin sheet';  
   
    DECLARE
        vn_TmpDayCtr number;
         TYPE nt_type IS TABLE OF number;
         nt nt_type := nt_type (2 ,(oTheSheetColumnInfo.count - 1) , (oTheSheetColumnInfo.count - 2));
    BEGIN
        vn_TmpDayCtr := 1;
        
        reco_web_functions.col_span := 0;
        
        IF NOT bSummaryReport THEN
          FOR colctr IN 2 .. (oTheSheetColumnInfo.count - 1)
          LOOP
            reco_web_functions.col_span :=
                reco_web_functions.col_span
                  + oTheSheetColumnInfo(colctr).num_child_cols;
            
            IF oTheSheetColumnInfo(colctr).shipment_date
                    != oTheSheetColumnInfo(colctr+1).shipment_date
            OR oTheSheetColumnInfo(colctr+1).shipment_date IS NULL
            THEN
              reco_web_functions.cell_attr := vc_Color_OddDayNorm;
              IF MOD(vn_TmpDayCtr,2) = 0
              THEN reco_web_functions.cell_attr := vc_Color_EvenDayNorm;
              END IF;
              
              reco_web_functions.add_header_column(
                TO_CHAR(oTheSheetColumnInfo(colctr).shipment_date,'DY DD-MON'));
              
              vn_TmpDayCtr := vn_TmpDayCtr + 1;
              
              reco_web_functions.col_span := 0;
            END IF;
          END LOOP;
        
        ELSIF bSummaryReport THEN
          -- JNL REPORTING CONDITION START
          FOR colctr IN 1..nt.count
          LOOP
            reco_web_functions.col_span :=
                reco_web_functions.col_span
                  + oTheSheetColumnInfo(colctr).num_child_cols;
            
            IF oTheSheetColumnInfo(colctr).shipment_date
                    != oTheSheetColumnInfo(colctr+1).shipment_date
            OR oTheSheetColumnInfo(colctr+1).shipment_date IS NULL
            THEN
              reco_web_functions.cell_attr := vc_Color_OddDayNorm;
              IF MOD(vn_TmpDayCtr,2) = 0
              THEN reco_web_functions.cell_attr := vc_Color_EvenDayNorm;
              END IF;
              
              reco_web_functions.add_header_column(
                TO_CHAR(oTheSheetColumnInfo(colctr).shipment_date,'DY DD-MON'));
              
              vn_TmpDayCtr := vn_TmpDayCtr + 1;
              
              reco_web_functions.col_span := 0;
            END IF;
          END LOOP;
          -- JNL REPORTING CONDITION END
          
        END IF;
        
      END;
  
  reco_web_functions.col_span :=
          oTheSheetColumnInfo(oTheSheetColumnInfo.count).num_child_cols;
  reco_web_functions.cell_attr := '';
  reco_web_functions.add_header_column(' ');
  
  reco_web_functions.print_header;
   thelocation := 'header';
  ---
  -- Header - Print each date shipment name and inventory header / etc
  ---
  
  reco_web_functions.clear_headers;
  
  DECLARE
    vn_TmpDayCtr number;
    vc_TmpTxtToPrint varchar2(1000);
    TYPE nt_type IS TABLE OF number;
    nt nt_type := nt_type (2 ,(oTheSheetColumnInfo.count - 1) , (oTheSheetColumnInfo.count - 2));

  BEGIN
    vn_TmpDayCtr := 0;
    
    IF NOT bSummaryReport THEN
  thelocation := 'docount';      
      FOR colctr IN 1 .. oTheSheetColumnInfo.count
      LOOP
        reco_web_functions.col_span :=
            oTheSheetColumnInfo(colctr).num_child_cols;
        
        IF oTheSheetColumnInfo(colctr).rptColTypeCode = 'PARTNAME'
        THEN
          reco_web_functions.cell_attr := '';
          vc_TmpTxtToPrint :=
              TO_CHAR(SYSDATE,'YYYY')||'<br>'||TO_CHAR(SYSDATE,'DD-MON');
                      
        ELSIF oTheSheetColumnInfo(colctr).rptColTypeCode = 'DAILYPARTINV'
        THEN
          reco_web_functions.cell_attr := vc_Color_InvText;
          vc_TmpTxtToPrint := 'Morning<br>INV';
  
        ELSIF oTheSheetColumnInfo(colctr).rptColTypeCode = 'DELIVEREDSHIP'
        THEN
          reco_web_functions.cell_attr := '';
          vc_TmpTxtToPrint :=
              '<A HREF="http://ebs.vincic-sf.grpsc.net:8000/pls/RECO/reco_web_info.display_shipment?p_shipment_id='||
              TO_CHAR(oTheSheetColumnInfo(colctr).shipment_id)||
              '" target="new">'||
              SUBSTR(oTheSheetColumnInfo(colctr).tracking_number,1,
                INSTR(oTheSheetColumnInfo(colctr).tracking_number,'-',1,3))||
              '<br>'||
              SUBSTR(oTheSheetColumnInfo(colctr).tracking_number,
                INSTR(oTheSheetColumnInfo(colctr).tracking_number,'-',1,3) + 1)||
              '-'||
              oTheSheetColumnInfo(colctr).shipment_status||
              '</A>';
        ELSIF oTheSheetColumnInfo(colctr).rptColTypeCode = 'PENDINGSHIP'
        THEN
          reco_web_functions.cell_attr := '';
          vc_TmpTxtToPrint :=
              '<A HREF="http://ebs.vincic-sf.grpsc.net:8000/pls/RECO/reco_web_info.display_shipment?p_shipment_id='||
              TO_CHAR(oTheSheetColumnInfo(colctr).shipment_id)||
              '" target="new">'||
              SUBSTR(oTheSheetColumnInfo(colctr).tracking_number,1,
                INSTR(oTheSheetColumnInfo(colctr).tracking_number,'-',1,3))||
              '<br>'||
              SUBSTR(oTheSheetColumnInfo(colctr).tracking_number,
                INSTR(oTheSheetColumnInfo(colctr).tracking_number,'-',1,3) + 1)||
              '-'||
              oTheSheetColumnInfo(colctr).STATE||
              '</A>';
        ELSIF oTheSheetColumnInfo(colctr).rptColTypeCode = 'DAYPARTPROPOSEDMFG'
        THEN
          reco_web_functions.cell_attr := vc_Color_InvText;
          vc_TmpTxtToPrint := 'Steel<br>Manuf';
          
        ELSIF oTheSheetColumnInfo(colctr).rptColTypeCode = 'ENDINVTOTAL'
        THEN
          reco_web_functions.cell_attr := vc_Color_InvText;
          vc_TmpTxtToPrint := 'Ending<br>INV';
          
        ELSIF oTheSheetColumnInfo(colctr).rptColTypeCode = 'NEGATIVEINV'
        THEN
          reco_web_functions.cell_attr := vc_Color_InvText;
          vc_TmpTxtToPrint := 'INV <br>Negative on';
          
        END IF;
        
        reco_web_functions.add_header_column(vc_TmpTxtToPrint);
        
        vn_TmpDayCtr := vn_TmpDayCtr + 1;
      END LOOP;
      
    ELSIF bSummaryReport THEN
    
      -- JNL REPORTING CONDITION START
        FOR colctr IN 1 .. oTheSheetColumnInfo.count
        LOOP
          reco_web_functions.col_span :=
              oTheSheetColumnInfo(colctr).num_child_cols;
          
          IF oTheSheetColumnInfo(colctr).rptColTypeCode = 'PARTNAME'
          THEN
            reco_web_functions.cell_attr := '';
            vc_TmpTxtToPrint :=
                TO_CHAR(SYSDATE,'YYYY')||'<br>'||TO_CHAR(SYSDATE,'DD-MON');
                        
          ELSIF oTheSheetColumnInfo(colctr).rptColTypeCode = 'DAILYPARTINV'
          THEN
            reco_web_functions.cell_attr := vc_Color_InvText;
            vc_TmpTxtToPrint := 'Morning<br>INV';
            
          ELSIF oTheSheetColumnInfo(colctr).rptColTypeCode = 'ENDINVTOTAL'
          THEN
            reco_web_functions.cell_attr := vc_Color_InvText;
            vc_TmpTxtToPrint := 'Ending<br>INV';
            
          ELSIF oTheSheetColumnInfo(colctr).rptColTypeCode = 'NEGATIVEINV'
          THEN
            reco_web_functions.cell_attr := vc_Color_InvText;
            vc_TmpTxtToPrint := 'INV <br>Negative on';
            
          END IF;
          
          --JNL REPORT IF CONDITION
        IF colctr = 1 OR colctr = 2 OR colctr = (oTheSheetColumnInfo.count ) OR colctr = (oTheSheetColumnInfo.count - 1) THEN
           reco_web_functions.add_header_column(vc_TmpTxtToPrint);
        END IF;
          
          vn_TmpDayCtr := vn_TmpDayCtr + 1;
        END LOOP;
       -- JNL REPORTING CONDITION END
    END IF;
    
  END;
   thelocation := 'header2';
  reco_web_functions.print_header;
  
  ---
  -- Header - Print B / G items
  ---
  
  reco_web_functions.clear_headers;
  
  DECLARE
    vn_TmpDayCtr number;
    vc_TmpTxtToPrint varchar2(1000);
    
    TYPE nt_type IS TABLE OF number;
	  nt nt_type := nt_type (2 ,(oTheSheetColumnInfo.count - 1) , (oTheSheetColumnInfo.count - 2));
    
    -- ************************************************************************************************ JNL START TOTWGHT
    PROCEDURE proc_PrintTotalWght
    IS
    BEGIN -- proc_PrintTotalWght
    
        IF NOT bSummaryReport THEN
          FOR colctr IN 1 .. oTheSheetColumnInfo.count
          LOOP
            
            IF oTheSheetColumnInfo(colctr).rptColTypeCode = 'PARTNAME'
            THEN
              reco_web_functions.col_span := 1;
              reco_web_functions.cell_attr := vc_Color_DelivStdTxt;
              reco_web_functions.add_data_column('ShipTot');                      
            
            ELSIF oTheSheetColumnInfo(colctr).rptColTypeCode = 'DAILYPARTINV'
            THEN
                reco_web_functions.col_span := 2;
                IF colctr = 2
                THEN reco_web_functions.col_span := 3;
                END IF;
                reco_web_functions.cell_attr := vc_Color_DelivStdTxt;
                reco_web_functions.add_data_column(' ');                            -- JNL END
            ELSIF oTheSheetColumnInfo(colctr).rptColTypeCode = 'DELIVEREDSHIP'
            THEN
              reco_web_functions.col_span := 2;
              reco_web_functions.cell_attr := vc_Color_DelivStdTxt;
                reco_web_functions.add_data_column(
                  TO_CHAR(ROUND(oTheSheetColumnInfo(colctr).ship_totwgt,2),
                          '9999.00')||' Tons');
  
            ELSIF oTheSheetColumnInfo(colctr).rptColTypeCode = 'PENDINGSHIP'
            THEN
              reco_web_functions.col_span := 2;
              reco_web_functions.cell_attr := vc_Color_DelivStdTxt;
  
                reco_web_functions.add_data_column(
                  TO_CHAR(ROUND(oTheSheetColumnInfo(colctr).ship_totwgt,2),
                          '9999.00')||' Tons');
  --          elsif oTheSheetColumnInfo(colctr).rptColTypeCode = 'DAYPARTPROPOSEDMFG'
  --          then
  -- 
  --              reco_web_functions.col_span := 1;
  --              reco_web_functions.cell_attr := vc_Color_DelivStdTxt;
  --              reco_web_functions.add_data_column(' ');                          -- JNL END
  
            ELSIF oTheSheetColumnInfo(colctr).rptColTypeCode = 'ENDINVTOTAL'
            THEN
                reco_web_functions.col_span := 2;
                reco_web_functions.cell_attr := vc_Color_DelivStdTxt;
                reco_web_functions.add_data_column(' ');                      
           
           ELSIF oTheSheetColumnInfo(colctr).rptColTypeCode = 'NEGATIVEINV'
            THEN
                reco_web_functions.col_span := 2;
                reco_web_functions.cell_attr := vc_Color_DelivStdTxt;
                reco_web_functions.add_data_column(' ');  
           
            END IF;
          END LOOP;
        
        -- JNL REPORTING CONDITION START
        ELSIF bSummaryReport THEN
          FOR colctr IN 1 .. oTheSheetColumnInfo.count
          LOOP
            
            IF oTheSheetColumnInfo(colctr).rptColTypeCode = 'PARTNAME'
            THEN
              reco_web_functions.col_span := 1;
              reco_web_functions.cell_attr := vc_Color_DelivStdTxt;
              --JNL REPORT IF CONDITION
              IF colctr = 1 OR colctr = 2 OR colctr = (oTheSheetColumnInfo.count ) OR colctr = (oTheSheetColumnInfo.count - 1) THEN
                reco_web_functions.add_data_column('ShipTot');                      
              END IF;
              
            ELSIF oTheSheetColumnInfo(colctr).rptColTypeCode = 'DAILYPARTINV'
            THEN
                reco_web_functions.col_span := 2;
                IF colctr = 2
                THEN reco_web_functions.col_span := 3;
                END IF;
                reco_web_functions.cell_attr := vc_Color_DelivStdTxt;
                
                --JNL REPORT IF CONDITION
                IF colctr = 1 OR colctr = 2 OR colctr = (oTheSheetColumnInfo.count ) OR colctr = (oTheSheetColumnInfo.count - 1) THEN
                 reco_web_functions.add_data_column(' ');                            -- JNL END
                END IF;
                
            ELSIF oTheSheetColumnInfo(colctr).rptColTypeCode = 'DELIVEREDSHIP'
            THEN
              reco_web_functions.col_span := 2;
              reco_web_functions.cell_attr := vc_Color_DelivStdTxt;
              
              --JNL REPORT IF CONDITION
              IF colctr = 1 OR colctr = 2 OR colctr = (oTheSheetColumnInfo.count ) OR colctr = (oTheSheetColumnInfo.count - 1) THEN
                reco_web_functions.add_data_column(
                  TO_CHAR(ROUND(oTheSheetColumnInfo(colctr).ship_totwgt,2),
                          '9999.00')||' Tons');
              END IF;
  
            ELSIF oTheSheetColumnInfo(colctr).rptColTypeCode = 'PENDINGSHIP'
            THEN
              reco_web_functions.col_span := 2;
              reco_web_functions.cell_attr := vc_Color_DelivStdTxt;
  
            --JNL REPORT IF CONDITION
              IF colctr = 1 OR colctr = 2 OR colctr = (oTheSheetColumnInfo.count ) OR colctr = (oTheSheetColumnInfo.count - 1) THEN
                
                reco_web_functions.add_data_column(
                  TO_CHAR(ROUND(oTheSheetColumnInfo(colctr).ship_totwgt,2),
                          '9999.00')||' Tons');
              END IF;
              
  --          elsif oTheSheetColumnInfo(colctr).rptColTypeCode = 'DAYPARTPROPOSEDMFG'
  --          then
  -- 
  --              reco_web_functions.col_span := 1;
  --              reco_web_functions.cell_attr := vc_Color_DelivStdTxt;
  --              reco_web_functions.add_data_column(' ');                          -- JNL END
  
            ELSIF oTheSheetColumnInfo(colctr).rptColTypeCode = 'ENDINVTOTAL'
            THEN
                reco_web_functions.col_span := 2;
                reco_web_functions.cell_attr := vc_Color_DelivStdTxt;
                
              --JNL REPORT IF CONDITION
              IF colctr = 1 OR colctr = 2 OR colctr = (oTheSheetColumnInfo.count ) OR colctr = (oTheSheetColumnInfo.count - 1) THEN
                reco_web_functions.add_data_column(' ');                      
              END IF;
              
           ELSIF oTheSheetColumnInfo(colctr).rptColTypeCode = 'NEGATIVEINV'
            THEN
                reco_web_functions.col_span := 2;
                reco_web_functions.cell_attr := vc_Color_DelivStdTxt;
                
                --JNL REPORT IF CONDITION
                IF colctr = 1 OR colctr = 2 OR colctr = (oTheSheetColumnInfo.count ) OR colctr = (oTheSheetColumnInfo.count - 1) THEN
                  reco_web_functions.add_data_column(' '); 
                END IF;
           
            END IF;
          END LOOP;
        END IF;
        -- JNL REPORTING CONDITION END
        
        reco_web_functions.print_datarow;
    END; -- proc_PrintTotalWght
-- ************************************************************************************************ JNL END TOTWGHT 

  BEGIN
    vn_TmpDayCtr := 0;
    proc_PrintTotalWght;                         -- JNL TOTAL Weight 8.0
      thelocation := 'sheetsummary';
    IF NOT bSummaryReport THEN
      FOR colctr IN 1 .. oTheSheetColumnInfo.count
      LOOP
        
        IF oTheSheetColumnInfo(colctr).rptColTypeCode = 'PARTNAME'
        THEN
          reco_web_functions.col_span := 1;
          reco_web_functions.cell_attr := vc_Color_InvText;
          vc_TmpTxtToPrint := '<b>Parts</b>';
          reco_web_functions.add_header_column(vc_TmpTxtToPrint);
        ELSIF oTheSheetColumnInfo(colctr).rptColTypeCode = 'DAILYPARTINV'
        THEN
          IF oTheSheetColumnInfo(colctr).num_child_cols = 3
          THEN
            reco_web_functions.col_span := 1;
            reco_web_functions.cell_attr := '';
            vc_TmpTxtToPrint := '<b>N</b>';
            reco_web_functions.add_header_column(vc_TmpTxtToPrint);
          END IF;
          reco_web_functions.col_span := 1;
          reco_web_functions.cell_attr := '';
          vc_TmpTxtToPrint := '<b>B</b>';
          reco_web_functions.add_header_column(vc_TmpTxtToPrint);
          reco_web_functions.col_span := 1;
          reco_web_functions.cell_attr := '';
          vc_TmpTxtToPrint := '<b>G</b>';
          reco_web_functions.add_header_column(vc_TmpTxtToPrint);
  --      elsif oTheSheetColumnInfo(colctr).rptColTypeCode = 'ENDINVTOTAL'
  --      then
  --        reco_web_functions.col_span := 1;
  --        reco_web_functions.cell_attr := '';
  --        vc_TmpTxtToPrint := '<b>B</b>';
  --        reco_web_functions.add_header_column(vc_TmpTxtToPrint);
  --        reco_web_functions.col_span := 1;
  --        reco_web_functions.cell_attr := '';
  --        vc_TmpTxtToPrint := '<b>G</b>';
  --        reco_web_functions.add_header_column(vc_TmpTxtToPrint);
        ELSIF oTheSheetColumnInfo(colctr).rptColTypeCode = 'DELIVEREDSHIP'
        THEN
          reco_web_functions.col_span := 1;
          reco_web_functions.cell_attr := '';
          vc_TmpTxtToPrint := '<b>B</b>';
          reco_web_functions.add_header_column(vc_TmpTxtToPrint);
          reco_web_functions.col_span := 1;
          reco_web_functions.cell_attr := '';
          vc_TmpTxtToPrint := '<b>G</b>';
          reco_web_functions.add_header_column(vc_TmpTxtToPrint);
        ELSIF oTheSheetColumnInfo(colctr).rptColTypeCode = 'PENDINGSHIP'
        THEN
          reco_web_functions.col_span := 1;
          reco_web_functions.cell_attr := '';
          vc_TmpTxtToPrint := '<b>B</b>';
          reco_web_functions.add_header_column(vc_TmpTxtToPrint);
          reco_web_functions.col_span := 1;
          reco_web_functions.cell_attr := '';
          vc_TmpTxtToPrint := '<b>G</b>';
          reco_web_functions.add_header_column(vc_TmpTxtToPrint);
        ELSIF oTheSheetColumnInfo(colctr).rptColTypeCode = 'DAYPARTPROPOSEDMFG'
        THEN
          reco_web_functions.col_span := 1;
          reco_web_functions.cell_attr := '';
          vc_TmpTxtToPrint := '<b>B</b>';
          reco_web_functions.add_header_column(vc_TmpTxtToPrint);
        ELSIF oTheSheetColumnInfo(colctr).rptColTypeCode = 'ENDINVTOTAL'
        THEN
          reco_web_functions.col_span := 1;
          reco_web_functions.cell_attr := '';
          vc_TmpTxtToPrint := '<b>B</b>';
          reco_web_functions.add_header_column(vc_TmpTxtToPrint);
          reco_web_functions.col_span := 1;
          reco_web_functions.cell_attr := '';
          vc_TmpTxtToPrint := '<b>G</b>';
          reco_web_functions.add_header_column(vc_TmpTxtToPrint);
        ELSIF oTheSheetColumnInfo(colctr).rptColTypeCode = 'NEGATIVEINV'
        THEN
          reco_web_functions.col_span := 1;
          reco_web_functions.cell_attr := '';
          vc_TmpTxtToPrint := ' ';
          reco_web_functions.add_header_column(vc_TmpTxtToPrint);
          reco_web_functions.col_span := 1;
          reco_web_functions.cell_attr := '';
          vc_TmpTxtToPrint := ' ';
          reco_web_functions.add_header_column(vc_TmpTxtToPrint);
        END IF;
        
        vn_TmpDayCtr := vn_TmpDayCtr + 1;
      END LOOP;
      
    -- JNL REPORTING CONDITION START 
    ELSIF bSummaryReport THEN    
      FOR colctr IN 1 .. oTheSheetColumnInfo.count
      LOOP
        
        IF oTheSheetColumnInfo(colctr).rptColTypeCode = 'PARTNAME'
        THEN
          reco_web_functions.col_span := 1;
          reco_web_functions.cell_attr := vc_Color_InvText;
          vc_TmpTxtToPrint := '<b>Parts</b>';
          reco_web_functions.add_header_column(vc_TmpTxtToPrint);
        ELSIF oTheSheetColumnInfo(colctr).rptColTypeCode = 'DAILYPARTINV'
        THEN
          IF oTheSheetColumnInfo(colctr).num_child_cols = 3
          THEN
            reco_web_functions.col_span := 1;
            reco_web_functions.cell_attr := '';
            vc_TmpTxtToPrint := '<b>N</b>';
            reco_web_functions.add_header_column(vc_TmpTxtToPrint);
          END IF;
          reco_web_functions.col_span := 1;
          reco_web_functions.cell_attr := '';
          vc_TmpTxtToPrint := '<b>B</b>';
          
          --JNL REPORT IF CONDITION
          IF colctr = 1 OR colctr = 2 OR colctr = (oTheSheetColumnInfo.count ) OR colctr = (oTheSheetColumnInfo.count - 1) THEN
            reco_web_functions.add_header_column(vc_TmpTxtToPrint);
          END IF;
          
          reco_web_functions.col_span := 1;
          reco_web_functions.cell_attr := '';
          vc_TmpTxtToPrint := '<b>G</b>';
          
          --JNL REPORT IF CONDITION
          IF colctr = 1 OR colctr = 2 OR colctr = (oTheSheetColumnInfo.count ) OR colctr = (oTheSheetColumnInfo.count - 1) THEN
            reco_web_functions.add_header_column(vc_TmpTxtToPrint);
          END IF;
          
  --      elsif oTheSheetColumnInfo(colctr).rptColTypeCode = 'ENDINVTOTAL'
  --      then
  --        reco_web_functions.col_span := 1;
  --        reco_web_functions.cell_attr := '';
  --        vc_TmpTxtToPrint := '<b>B</b>';
  --        reco_web_functions.add_header_column(vc_TmpTxtToPrint);
  --        reco_web_functions.col_span := 1;
  --        reco_web_functions.cell_attr := '';
  --        vc_TmpTxtToPrint := '<b>G</b>';
  --        reco_web_functions.add_header_column(vc_TmpTxtToPrint);
  
        -- JNL COMMENTED THE BELOW SECTION - REPORTING - 6/13/2017
  --      elsif oTheSheetColumnInfo(colctr).rptColTypeCode = 'DELIVEREDSHIP'
  --      then
  --        reco_web_functions.col_span := 1;
  --        reco_web_functions.cell_attr := '';
  --        vc_TmpTxtToPrint := '<b>B</b>';
  --        reco_web_functions.add_header_column(vc_TmpTxtToPrint);
  --        reco_web_functions.col_span := 1;
  --        reco_web_functions.cell_attr := '';
  --        vc_TmpTxtToPrint := '<b>G</b>';
  --        
  --        --JNL REPORT IF CONDITION
  --        if colctr = 1 OR colctr = 2 OR colctr = (oTheSheetColumnInfo.count ) OR colctr = (oTheSheetColumnInfo.count - 1) then
  --          reco_web_functions.add_header_column(vc_TmpTxtToPrint);
  --        end if;  
  --        
  --      elsif oTheSheetColumnInfo(colctr).rptColTypeCode = 'PENDINGSHIP'
  --      then
  --        reco_web_functions.col_span := 1;
  --        reco_web_functions.cell_attr := '';
  --        vc_TmpTxtToPrint := '<b>B</b>';
  --        reco_web_functions.add_header_column(vc_TmpTxtToPrint);
  --        reco_web_functions.col_span := 1;
  --        reco_web_functions.cell_attr := '';
  --        vc_TmpTxtToPrint := '<b>G</b>';
  --        
  --         --JNL REPORT IF CONDITION
  --        if colctr = 1 OR colctr = 2 OR colctr = (oTheSheetColumnInfo.count ) OR colctr = (oTheSheetColumnInfo.count - 1) then
  --          reco_web_functions.add_header_column(vc_TmpTxtToPrint);
  --        end if;
  --        
  --      elsif oTheSheetColumnInfo(colctr).rptColTypeCode = 'DAYPARTPROPOSEDMFG'
  --      then
  --        reco_web_functions.col_span := 1;
  --        reco_web_functions.cell_attr := '';
  --        vc_TmpTxtToPrint := '<b>B</b>';
  --        
  --         --JNL REPORT IF CONDITION
  --        if colctr = 1 OR colctr = 2 OR colctr = (oTheSheetColumnInfo.count ) OR colctr = (oTheSheetColumnInfo.count - 1) then
  --          reco_web_functions.add_header_column(vc_TmpTxtToPrint);
  --        end if;
        
        ELSIF oTheSheetColumnInfo(colctr).rptColTypeCode = 'ENDINVTOTAL'
        THEN
          reco_web_functions.col_span := 1;
          reco_web_functions.cell_attr := '';
          vc_TmpTxtToPrint := '<b>B</b>';
          
          --JNL REPORT IF CONDITION
          IF colctr = 1 OR colctr = 2 OR colctr = (oTheSheetColumnInfo.count ) OR colctr = (oTheSheetColumnInfo.count - 1) THEN
           reco_web_functions.add_header_column(vc_TmpTxtToPrint);
          END IF;
          
          reco_web_functions.col_span := 1;
          reco_web_functions.cell_attr := '';
          
          --JNL REPORT IF CONDITION
          IF colctr = 1 OR colctr = 2 OR colctr = (oTheSheetColumnInfo.count ) OR colctr = (oTheSheetColumnInfo.count - 1) THEN
            vc_TmpTxtToPrint := '<b>G</b>';
          END IF;
          
          reco_web_functions.add_header_column(vc_TmpTxtToPrint);
        ELSIF oTheSheetColumnInfo(colctr).rptColTypeCode = 'NEGATIVEINV'
        THEN
          reco_web_functions.col_span := 1;
          reco_web_functions.cell_attr := '';
          vc_TmpTxtToPrint := ' ';
          reco_web_functions.add_header_column(vc_TmpTxtToPrint);
          reco_web_functions.col_span := 1;
          reco_web_functions.cell_attr := '';
          vc_TmpTxtToPrint := ' ';
          
           --JNL REPORT IF CONDITION
          IF colctr = 1 OR colctr = 2 OR colctr = (oTheSheetColumnInfo.count ) OR colctr = (oTheSheetColumnInfo.count - 1) THEN
            reco_web_functions.add_header_column(vc_TmpTxtToPrint);
          END IF;
          
        END IF;
        
        vn_TmpDayCtr := vn_TmpDayCtr + 1;
      END LOOP;
      
    END IF;
    -- JNL REPORTING CONDITION END
    
  END;
  
  reco_web_functions.print_header;
  
  ---
  -- If there are no parts / rows, then we can exit early
  -- (and also prevent possible errors of partqty = 0)
  ---
    thelocation := 'parts2';
  DECLARE
    vn_TotalPartRows number;
  BEGIN
    SELECT COUNT(*) INTO vn_TotalPartRows FROM reco_rstx_tmpshpcalparts;

    IF vn_TotalPartRows = 0
    THEN
      reco_web_functions.clear_headers;
      
      reco_web_functions.col_span := 9;
      reco_web_functions.cell_attr := '';
      reco_web_functions.add_header_column(
        'Steel Shipments');
      reco_web_functions.print_header;
      
      reco_web_functions.clear_headers;
      reco_web_functions.col_span := 9;
      reco_web_functions.cell_attr := '';
      reco_web_functions.add_header_column(
        'There are no pending Shipments or Parts that are shown');
      reco_web_functions.print_header;
      
      reco_web_functions.clear_headers;
      reco_web_functions.col_span := 9;
      reco_web_functions.cell_attr := '';
      reco_web_functions.add_header_column(
        'for parameter dates '||TO_CHAR(vd_FirstDateShown,'DD-MON-YYYY')||
        ' to '||TO_CHAR(vd_LastDateShown,'DD-MON-YYYY')||', so report is blank');
      reco_web_functions.print_header;
      reco_web_Functions.close_spreadsheet;
      RETURN;
    END IF;
  END;
  
  ---
  -- Body - Print part rows
  ---
  
  DECLARE
    vb_PrevPartRowExists BOOLEAN;
    vr_PrevPartRow reco_rstx_tmpshpcalparts%ROWTYPE;
    
    vn_TmpNPInvQty number;
    vn_TmpBPInvQty number;
    vn_TmpGPInvQty number;
    
    vn_TmpDayCtr number;
       
    CURSOR cur_ThisPartVals(pi_GivenBlackId IN number,
                            pi_GivenGalvId IN number)
    IS
      SELECT  rs.truck_date shipment_date,
              NVL(rs.tracking_number,rst.stop_identifier) tracking_number,
              rst.shipment_id,
              CASE
              WHEN rs.truck_status = 'D'
              THEN 1
              ELSE 2
              END sortord_shipstat,
              rs.truck_status shipment_status,
              SUM(NVL(rspblack.quantity,0)) totblack,
              SUM(NVL(rspgalv.quantity,0)) totgalv
      FROM  reco_truck rs, reco_truckstop rst,
            reco_shipment_parts_v rspblack,
            reco_shipment_parts_v rspgalv
      WHERE   rst.shipment_id = rspblack.shipment_id (+)
      AND     rspblack.part_id (+) = pi_GivenBlackId
      AND     rspblack.orig_subinventory_code (+) = 'RSTX'
      AND     rst.shipment_id = rspgalv.shipment_id (+)
      AND     rspgalv.part_id (+) = pi_GivenGalvId
      AND     rspgalv.orig_subinventory_code (+) = 'RSTX'
      AND     rs.truck_status IN ('A','H','B','D')
      AND     rs.truck_date >= vd_FirstDateShown
      AND     rs.truck_date <= vd_LastDateShown
      AND     rst.stop_truck_id = rs.truck_id
      GROUP BY  rs.truck_date,
                NVL(rs.tracking_number,rst.stop_identifier),
                rst.shipment_id,
                CASE
                WHEN rs.truck_status = 'D'
                THEN 1
                ELSE 2
                END,
                rs.truck_status
      HAVING      SUM(NVL(rspblack.quantity,0)) > 0
      OR          SUM(NVL(rspgalv.quantity,0)) > 0
      ORDER BY  rs.truck_date,
                CASE
                WHEN rs.truck_status = 'D'
                THEN 1
                ELSE 2
                END,
                NVL(rs.tracking_number,rst.stop_identifier),
                rst.shipment_id;
    
    TYPE coll_ThisPartVals IS TABLE OF cur_ThisPartVals%ROWTYPE;
    oThisPartVals coll_ThisPartVals; -- Fetched, so don't initialize
    nCtrPartVals number;




-- ************************************************************************************************* -- JNL 6.0    
    PROCEDURE proc_PrintTwoWeightsRowsSP( p_partType IN VARCHAR2)
    IS
      v_partType VARCHAR2(20);
    BEGIN -- proc_PrintTwoWeightsRowsSP
      
      v_partType := p_partType;
      
      FOR rowctr IN 1 .. 1
      LOOP
       
       IF NOT bSummaryReport THEN
          FOR colctr IN 1 .. oTheSheetColumnInfo.count
          LOOP
            
            IF oTheSheetColumnInfo(colctr).rptColTypeCode = 'PARTNAME'
            THEN
              reco_web_functions.col_span := 1;
              reco_web_functions.cell_attr := '';
              IF rowctr = 1
              THEN reco_web_functions.add_data_column('StlTons');
              END IF;
  
            ELSIF oTheSheetColumnInfo(colctr).rptColTypeCode = 'DAILYPARTINV'
            THEN
              IF rowctr = 1
              THEN
                IF colctr = 2
                THEN
                  reco_web_functions.col_span := 1;
                  reco_web_functions.cell_attr := '';
                  
                  IF v_partType LIKE ('S504%') THEN                         
                    reco_web_functions.add_data_column(           
                      TO_CHAR(
                        ROUND(oTheSheetColumnInfo(colctr).daystrt_npb_tonn,2),
                        '9999.00')||'T');
                  ELSIF v_partType LIKE ('D504%') THEN
                    reco_web_functions.add_data_column(' ');
                    
                  ELSIF v_partType LIKE ('S506%') THEN
                    reco_web_functions.add_data_column(           
                      TO_CHAR(
                        ROUND(oTheSheetColumnInfo(colctr).daystrt506_npb_tonn,2),
                        '9999.00')||'T');
                  ELSIF v_partType LIKE ('D506%') THEN
                    reco_web_functions.add_data_column(' ');
                  END IF;
                  
                END IF;
                
                reco_web_functions.col_span := 1;                                
                reco_web_functions.cell_attr := '';
                
                 IF v_partType LIKE ('S504%') THEN                         
                    reco_web_functions.add_data_column(
                      TO_CHAR(
                        ROUND(oTheSheetColumnInfo(colctr).daystrt_spb_tonn,2),
                        '9999.00')||'T');
                 ELSIF v_partType LIKE ('D504%') THEN
                     reco_web_functions.add_data_column(           
                       TO_CHAR(
                         ROUND(oTheSheetColumnInfo(colctr).daystrt_dpb_tonn,2),
                         '9999.00')||'T');
                  ELSIF v_partType LIKE ('S506%') THEN
                    reco_web_functions.add_data_column(           
                      TO_CHAR(
                        ROUND(oTheSheetColumnInfo(colctr).daystrt506_spb_tonn,2),
                        '9999.00')||'T');
                  ELSIF v_partType LIKE ('D506%') THEN
                    reco_web_functions.add_data_column(           
                      TO_CHAR(
                        ROUND(oTheSheetColumnInfo(colctr).daystrt506_dpb_tonn,2),
                        '9999.00')||'T');
                  END IF;
                
                reco_web_functions.col_span := 1;                                  
                reco_web_functions.cell_attr := '';
                IF v_partType LIKE ('S504%') THEN                         
                    reco_web_functions.add_data_column(
                      TO_CHAR(
                        ROUND(oTheSheetColumnInfo(colctr).daystrt_spg_tonn,2),
                        '9999.00')||'T');
                  ELSIF v_partType LIKE ('D504%') THEN
                    reco_web_functions.add_data_column(           
                      TO_CHAR(
                        ROUND(oTheSheetColumnInfo(colctr).daystrt_dpg_tonn,2),
                        '9999.00')||'T');
                  ELSIF v_partType LIKE ('S506%') THEN
                    reco_web_functions.add_data_column(           
                      TO_CHAR(
                        ROUND(oTheSheetColumnInfo(colctr).daystrt506_spg_tonn,2),
                        '9999.00')||'T');
                  ELSIF v_partType LIKE ('D506%') THEN
                    reco_web_functions.add_data_column(           
                      TO_CHAR(
                        ROUND(oTheSheetColumnInfo(colctr).daystrt506_dpg_tonn,2),
                        '9999.00')||'T');
                  END IF;
             
              ELSIF rowctr = 2                                                      
              THEN
                reco_web_functions.col_span := 2;
                IF colctr = 2
                THEN reco_web_functions.col_span := 3;
                END IF;
                reco_web_functions.cell_attr := '';
                reco_web_functions.add_data_column(' ');                           
              END IF;                                                               
  
            ELSIF oTheSheetColumnInfo(colctr).rptColTypeCode = 'DELIVEREDSHIP'
            THEN
              reco_web_functions.col_span := 2;
              reco_web_functions.cell_attr := '';
              IF rowctr = 1
              THEN
                reco_web_functions.add_data_column(
                  TO_CHAR(ROUND(WeightForPartType(oTheSheetColumnInfo(colctr).shipment_id, v_partType),2),         --oTheSheetColumnInfoSP(colctr).ship_stlwgt,2),
                          '9999.00')||' Tons');
              END IF;
            ELSIF oTheSheetColumnInfo(colctr).rptColTypeCode = 'PENDINGSHIP'
            THEN
              reco_web_functions.col_span := 2;
              reco_web_functions.cell_attr := '';
              IF rowctr = 1
              THEN
                reco_web_functions.add_data_column(
                  TO_CHAR(ROUND(WeightForPartType(oTheSheetColumnInfo(colctr).shipment_id, v_partType),2),         --oTheSheetColumnInfo(colctr).ship_stlwgt,2),
                          '9999.00')||' Tons');
              END IF; 
            
            ELSIF oTheSheetColumnInfo(colctr).rptColTypeCode = 'ENDINVTOTAL'
            THEN
              IF rowctr = 1
              THEN
                reco_web_functions.col_span := 1;
                reco_web_functions.cell_attr := '';
                IF v_partType LIKE ('S504%') THEN                         
                    reco_web_functions.add_data_column(
                      TO_CHAR(
                        ROUND(oTheSheetColumnInfo(colctr).daystrt_spb_tonn,2),
                        '9999.00')||'T');
                  ELSIF v_partType LIKE ('D504%') THEN
                    reco_web_functions.add_data_column(           
                      TO_CHAR(
                        ROUND(oTheSheetColumnInfo(colctr).daystrt_dpb_tonn,2),
                        '9999.00')||'T');
                  ELSIF v_partType LIKE ('S506%') THEN
                    reco_web_functions.add_data_column(           
                      TO_CHAR(
                        ROUND(oTheSheetColumnInfo(colctr).daystrt506_spb_tonn,2),
                        '9999.00')||'T');
                  ELSIF v_partType LIKE ('D506%') THEN
                    reco_web_functions.add_data_column(           
                      TO_CHAR(
                        ROUND(oTheSheetColumnInfo(colctr).daystrt506_dpb_tonn,2),
                        '9999.00')||'T');
                END IF;
                
                reco_web_functions.col_span := 1;
                reco_web_functions.cell_attr := '';
                
                IF v_partType LIKE ('S504%') THEN                         -- JNL NEW WRITE UP
                    reco_web_functions.add_data_column(
                      TO_CHAR(
                        ROUND(oTheSheetColumnInfo(colctr).daystrt_spg_tonn,2),
                        '9999.00')||'T');
                  ELSIF v_partType LIKE ('D504%') THEN
                    reco_web_functions.add_data_column(           
                      TO_CHAR(
                        ROUND(oTheSheetColumnInfo(colctr).daystrt_dpg_tonn,2),
                        '9999.00')||'T');
                  ELSIF v_partType LIKE ('S506%') THEN
                    reco_web_functions.add_data_column(           
                      TO_CHAR(
                        ROUND(oTheSheetColumnInfo(colctr).daystrt506_spg_tonn,2),
                        '9999.00')||'T');
                  ELSIF v_partType LIKE ('D506%') THEN
                    reco_web_functions.add_data_column(           
                      TO_CHAR(
                        ROUND(oTheSheetColumnInfo(colctr).daystrt506_dpg_tonn,2),
                        '9999.00')||'T');
                END IF;
                  
              ELSIF rowctr = 2                                                -- JNL START
              THEN
                reco_web_functions.col_span := 1;
                reco_web_functions.cell_attr := '';
                reco_web_functions.add_data_column(' ');                      -- JNL END
              END IF;
              
              ELSIF oTheSheetColumnInfo(colctr).rptColTypeCode = 'NEGATIVEINV'
              THEN
                reco_web_functions.col_span := 2;
                reco_web_functions.cell_attr := '';
                IF rowctr = 1
                THEN
                  reco_web_functions.add_data_column(' ');
                ELSIF rowctr = 2                                                -- JNL START
                THEN
                  reco_web_functions.col_span := 2;
                  reco_web_functions.cell_attr := '';
                  reco_web_functions.add_data_column(' ');                      -- JNL END
              END IF;
              
            END IF;
          END LOOP;
        
        ELSIF bSummaryReport THEN
          -- JNL REPORTING CONDITION START
          FOR colctr IN 1 .. oTheSheetColumnInfo.count
          LOOP
            
            IF oTheSheetColumnInfo(colctr).rptColTypeCode = 'PARTNAME' AND
               (colctr = 1 OR colctr = 2 OR colctr = (oTheSheetColumnInfo.count ) OR colctr = (oTheSheetColumnInfo.count - 1))
            THEN
              reco_web_functions.col_span := 1;
              reco_web_functions.cell_attr := '';
              IF rowctr = 1 
              THEN reco_web_functions.add_data_column('StlTons');
              END IF;
  
            ELSIF oTheSheetColumnInfo(colctr).rptColTypeCode = 'DAILYPARTINV' AND
               (colctr = 1 OR colctr = 2 OR colctr = (oTheSheetColumnInfo.count ) OR colctr = (oTheSheetColumnInfo.count - 1))
            THEN
              IF rowctr = 1
              THEN
                IF colctr = 2 
                THEN
                  reco_web_functions.col_span := 1;
                  reco_web_functions.cell_attr := '';
                  
                  IF v_partType LIKE ('S504%')  THEN                         
                    
                    reco_web_functions.add_data_column(           
                      TO_CHAR(
                        ROUND(oTheSheetColumnInfo(colctr).daystrt_npb_tonn,2),
                        '9999.00')||'T');
                  ELSIF v_partType LIKE ('D504%') THEN
                    
                    reco_web_functions.add_data_column(' ');
                    
                  ELSIF v_partType LIKE ('S506%') THEN
                    
                    reco_web_functions.add_data_column(           
                      TO_CHAR(
                        ROUND(oTheSheetColumnInfo(colctr).daystrt506_npb_tonn,2),
                        '9999.00')||'T');
                        
                  ELSIF v_partType LIKE ('D506%') THEN
                    reco_web_functions.add_data_column(' ');
                  END IF;
                  
                END IF;
                
                reco_web_functions.col_span := 1;                                
                reco_web_functions.cell_attr := '';
                
                 IF v_partType LIKE ('S504%') THEN                         
                    
                    reco_web_functions.add_data_column(
                      TO_CHAR(
                        ROUND(oTheSheetColumnInfo(colctr).daystrt_spb_tonn,2),
                        '9999.00')||'T');
                        
                 ELSIF v_partType LIKE ('D504%')THEN
                     reco_web_functions.add_data_column(           
                       TO_CHAR(
                         ROUND(oTheSheetColumnInfo(colctr).daystrt_dpb_tonn,2),
                         '9999.00')||'T');
                  ELSIF v_partType LIKE ('S506%') THEN
                    reco_web_functions.add_data_column(           
                      TO_CHAR(
                        ROUND(oTheSheetColumnInfo(colctr).daystrt506_spb_tonn,2),
                        '9999.00')||'T');
                  ELSIF v_partType LIKE ('D506%') THEN
                    reco_web_functions.add_data_column(           
                      TO_CHAR(
                        ROUND(oTheSheetColumnInfo(colctr).daystrt506_dpb_tonn,2),
                        '9999.00')||'T');
                  END IF;
                
                reco_web_functions.col_span := 1;                                  
                reco_web_functions.cell_attr := '';
                IF v_partType LIKE ('S504%') THEN                         
                    reco_web_functions.add_data_column(
                      TO_CHAR(
                        ROUND(oTheSheetColumnInfo(colctr).daystrt_spg_tonn,2),
                        '9999.00')||'T');
                  ELSIF v_partType LIKE ('D504%') THEN
                    reco_web_functions.add_data_column(           
                      TO_CHAR(
                        ROUND(oTheSheetColumnInfo(colctr).daystrt_dpg_tonn,2),
                        '9999.00')||'T');
                  ELSIF v_partType LIKE ('S506%') THEN
                    reco_web_functions.add_data_column(           
                      TO_CHAR(
                        ROUND(oTheSheetColumnInfo(colctr).daystrt506_spg_tonn,2),
                        '9999.00')||'T');
                  ELSIF v_partType LIKE ('D506%') THEN
                    reco_web_functions.add_data_column(           
                      TO_CHAR(
                        ROUND(oTheSheetColumnInfo(colctr).daystrt506_dpg_tonn,2),
                        '9999.00')||'T');
                  END IF;
             
              ELSIF rowctr = 2                                                      
              THEN
                reco_web_functions.col_span := 2;
                IF colctr = 2
                THEN reco_web_functions.col_span := 3;
                END IF;
                reco_web_functions.cell_attr := '';
                reco_web_functions.add_data_column(' ');                           
              END IF;                                                               
            
            ELSIF oTheSheetColumnInfo(colctr).rptColTypeCode = 'ENDINVTOTAL' AND
               (colctr = 1 OR colctr = 2 OR colctr = (oTheSheetColumnInfo.count ) OR colctr = (oTheSheetColumnInfo.count - 1))
            THEN
              IF rowctr = 1
              THEN
                reco_web_functions.col_span := 1;
                reco_web_functions.cell_attr := '';
                IF v_partType LIKE ('S504%') THEN                         
                    reco_web_functions.add_data_column(
                      TO_CHAR(
                        ROUND(oTheSheetColumnInfo(colctr).daystrt_spb_tonn,2),
                        '9999.00')||'T');
                  ELSIF v_partType LIKE ('D504%') THEN
                    reco_web_functions.add_data_column(           
                      TO_CHAR(
                        ROUND(oTheSheetColumnInfo(colctr).daystrt_dpb_tonn,2),
                        '9999.00')||'T');
                  ELSIF v_partType LIKE ('S506%') THEN
                    reco_web_functions.add_data_column(           
                      TO_CHAR(
                        ROUND(oTheSheetColumnInfo(colctr).daystrt506_spb_tonn,2),
                        '9999.00')||'T');
                  ELSIF v_partType LIKE ('D506%') THEN
                    reco_web_functions.add_data_column(           
                      TO_CHAR(
                        ROUND(oTheSheetColumnInfo(colctr).daystrt506_dpb_tonn,2),
                        '9999.00')||'T');
                END IF;
                
                reco_web_functions.col_span := 1;
                reco_web_functions.cell_attr := '';
                
                IF v_partType LIKE ('S504%') THEN                         -- JNL NEW WRITE UP
                    reco_web_functions.add_data_column(
                      TO_CHAR(
                        ROUND(oTheSheetColumnInfo(colctr).daystrt_spg_tonn,2),
                        '9999.00')||'T');
                  ELSIF v_partType LIKE ('D504%') THEN
                    reco_web_functions.add_data_column(           
                      TO_CHAR(
                        ROUND(oTheSheetColumnInfo(colctr).daystrt_dpg_tonn,2),
                        '9999.00')||'T');
                  ELSIF v_partType LIKE ('S506%') THEN
                    reco_web_functions.add_data_column(           
                      TO_CHAR(
                        ROUND(oTheSheetColumnInfo(colctr).daystrt506_spg_tonn,2),
                        '9999.00')||'T');
                  ELSIF v_partType LIKE ('D506%') THEN
                    reco_web_functions.add_data_column(           
                      TO_CHAR(
                        ROUND(oTheSheetColumnInfo(colctr).daystrt506_dpg_tonn,2),
                        '9999.00')||'T');
                END IF;
                  
              ELSIF rowctr = 2                                           -- JNL START
              THEN
                reco_web_functions.col_span := 1;
                reco_web_functions.cell_attr := '';
                reco_web_functions.add_data_column(' ');                      -- JNL END
              END IF;
              
              ELSIF oTheSheetColumnInfo(colctr).rptColTypeCode = 'NEGATIVEINV' AND
               (colctr = 1 OR colctr = 2 OR colctr = (oTheSheetColumnInfo.count ) OR colctr = (oTheSheetColumnInfo.count - 1))
              THEN
                reco_web_functions.col_span := 2;
                reco_web_functions.cell_attr := '';
                IF rowctr = 1 
                THEN
                  reco_web_functions.add_data_column(' ');
                ELSIF rowctr = 2                                                -- JNL START
                THEN
                  reco_web_functions.col_span := 2;
                  reco_web_functions.cell_attr := '';
                  reco_web_functions.add_data_column(' ');                      -- JNL END
              END IF;
              
            END IF;
          END LOOP;
        
        END IF;
        -- JNL REPORTING CONDITION END
        
        reco_web_functions.print_datarow;
      END LOOP;
    END; -- proc_PrintTwoWeightsRowsSP
-- ------------------------------------------------------------------------------------------------------------------------------
-- ------------------------------------------------------------------------------------------------------------------------------
FUNCTION getFirstNegativeDateText(
         sectionorder IN number, 
         pi_partName IN VARCHAR2)
RETURN VARCHAR2
IS
    vc_FirstNegativeDateText VARCHAR2(100);
    vb_FirstNegativeDateSet BOOLEAN;
    vc_PartName VARCHAR2(100);
BEGIN
    vb_FirstNegativeDateSet := FALSE;
    vc_PartName := '';
    
    FOR rec_CurrPartRow  IN
    (
      SELECT *
      FROM reco_rstx_tmpshpcalparts 
      WHERE 
           n_PartNumLen BETWEEN 4 AND 34        -- JNL 4.0
           --and sortorder = sectionorder
           AND reco_rstx_tmpshpcalparts.G_PARTNAME = pi_partName
      ORDER BY  sortorder,          -- 1=S504 parts, 2=D504 parts, 3=s506, 4=d506, 5=AllOther parts
                g_partpunch,
                g_parttype,
                g_partnumlen
    )
    LOOP
          
      vb_FirstNegativeDateSet := FALSE;
      vc_PartName := rec_CurrPartRow.G_PARTNAME;
      vn_TmpNPInvQty := rec_CurrPartRow.n_originvqty;
      vn_TmpBPInvQty := rec_CurrPartRow.b_originvqty;
      vn_TmpGPInvQty := rec_CurrPartRow.g_originvqty;
            
      OPEN cur_ThisPartVals(rec_CurrPartRow.b_partid,
                            rec_CurrPartRow.g_partid);
      FETCH cur_ThisPartVals BULK COLLECT INTO oThisPartVals;
      CLOSE cur_ThisPartVals;
      
      nCtrPartVals := 1;
      
      FOR colctr IN 1 .. oTheSheetColumnInfo.count
      LOOP     
      
        IF oTheSheetColumnInfo(colctr).rptColTypeCode = 'DAILYPARTINV'
        THEN
      
            IF ( vn_TmpGPInvQty < 0 AND vb_FirstNegativeDateSet = FALSE  )
              THEN vc_FirstNegativeDateText := ((TO_CHAR(oTheSheetColumnInfo(colctr).shipment_date,'DY DD-MON')));
                   vb_FirstNegativeDateSet := TRUE;
                  EXIT;
            END IF;
                   
            IF ( vn_TmpBPInvQty < 0 AND vb_FirstNegativeDateSet = FALSE )
                THEN vc_FirstNegativeDateText := ((TO_CHAR(oTheSheetColumnInfo(colctr).shipment_date,'DY DD-MON')));
                     vb_FirstNegativeDateSet := TRUE;
                EXIT;
            END IF; 
            
        ELSIF oTheSheetColumnInfo(colctr).rptColTypeCode = 'DELIVEREDSHIP'
        THEN
          IF nCtrPartVals <= oThisPartVals.count
          AND oThisPartVals(nCtrPartVals).shipment_id =
                oTheSheetColumnInfo(colctr).shipment_id
          THEN
          
              -- ---------------------------------------------------------------------------------------------------------
              -- ---------------------------------------------------------------------------------------------------------
              IF ( oThisPartVals(nCtrPartVals).totgalv < 0 AND vb_FirstNegativeDateSet = FALSE  )
              THEN vc_FirstNegativeDateText := ((TO_CHAR(oTheSheetColumnInfo(colctr).shipment_date,'DY DD-MON')));
                   vb_FirstNegativeDateSet := TRUE;
                  EXIT;
              END IF;
                     
              IF ( oThisPartVals(nCtrPartVals).totblack < 0 AND vb_FirstNegativeDateSet = FALSE )
                  THEN vc_FirstNegativeDateText := ((TO_CHAR(oTheSheetColumnInfo(colctr).shipment_date,'DY DD-MON')));
                       vb_FirstNegativeDateSet := TRUE;
                  EXIT;
              END IF; 
              -- ---------------------------------------------------------------------------------------------------------
              -- ---------------------------------------------------------------------------------------------------------
              
              nCtrPartVals := nCtrPartVals + 1;

          END IF;
        ELSIF oTheSheetColumnInfo(colctr).rptColTypeCode = 'PENDINGSHIP'
        THEN
          IF nCtrPartVals <= oThisPartVals.count
          AND oThisPartVals(nCtrPartVals).shipment_id =
                oTheSheetColumnInfo(colctr).shipment_id
          THEN
            IF oThisPartVals(nCtrPartVals).totblack != 0
            THEN
              vn_TmpBPInvQty := vn_TmpBPInvQty - oThisPartVals(nCtrPartVals).totblack;
            END IF;
            
            IF oThisPartVals(nCtrPartVals).totgalv != 0
            THEN
              vn_TmpGPInvQty := vn_TmpGPInvQty - oThisPartVals(nCtrPartVals).totgalv;
            END IF;
            
            nCtrPartVals := nCtrPartVals + 1;
            
            -- ---------------------------------------------------------------------------------------------------------
            -- ---------------------------------------------------------------------------------------------------------
            IF ( vn_TmpGPInvQty < 0 AND vb_FirstNegativeDateSet = FALSE  )
              THEN vc_FirstNegativeDateText := ((TO_CHAR(oTheSheetColumnInfo(colctr).shipment_date,'DY DD-MON')));
                   vb_FirstNegativeDateSet := TRUE;
                  EXIT;
            END IF;
                   
            IF ( vn_TmpBPInvQty < 0 AND vb_FirstNegativeDateSet = FALSE )
                THEN vc_FirstNegativeDateText := ((TO_CHAR(oTheSheetColumnInfo(colctr).shipment_date,'DY DD-MON')));
                     vb_FirstNegativeDateSet := TRUE;
                EXIT;
            END IF;
            -- ---------------------------------------------------------------------------------------------------------
            -- ---------------------------------------------------------------------------------------------------------

          END IF;
            
        END IF;
      END LOOP;
thelocation := 'partrow';
--      vr_PrevPartRow := rec_CurrPartRow;
    
    END LOOP; 
    
RETURN vc_FirstNegativeDateText;   
EXCEPTION
WHEN OTHERS THEN
   raise_application_error(-20001,'An error was encountered - '||thelocation||':'||SQLCODE||' -ERROR- '||SQLERRM);
END;
-- -------------------------------------------------------------------------------------------------------------------------------- ------------------------------------------------------------------------------------------------------------------------------
-- ------------------------------------------------------------------------------------------------------------------------------
FUNCTION getEndInvNumber(
         sectionorder IN number, 
         pi_partName IN VARCHAR2,
         pi_partType IN VARCHAR2)
RETURN NUMBER
IS
    vc_TotalEndInvNumber NUMBER;
    vb_FirstNegativeDateSet BOOLEAN;
    vc_PartName VARCHAR2(100);
BEGIN
    vc_TotalEndInvNumber := 0;
    vc_PartName := ' ';
    
    FOR rec_CurrPartRow  IN
    (
      SELECT *
      FROM reco_rstx_tmpshpcalparts 
      WHERE 
           n_PartNumLen BETWEEN 4 AND 34        -- JNL 4.0
           AND sortorder = sectionorder
           AND reco_rstx_tmpshpcalparts.G_PARTNAME = pi_partName
      ORDER BY  sortorder,          -- 1=S504 parts, 2=D504 parts, 3=s506, 4=d506, 5=AllOther parts
                g_partpunch,
                g_parttype,
                g_partnumlen
    )
    LOOP
          
      vc_PartName := rec_CurrPartRow.G_PARTNAME;
      vn_TmpNPInvQty := rec_CurrPartRow.n_originvqty;
      vn_TmpBPInvQty := rec_CurrPartRow.b_originvqty;
      vn_TmpGPInvQty := rec_CurrPartRow.g_originvqty;
      
      OPEN cur_ThisPartVals(rec_CurrPartRow.b_partid,
                            rec_CurrPartRow.g_partid);
      FETCH cur_ThisPartVals BULK COLLECT INTO oThisPartVals;
      CLOSE cur_ThisPartVals;
      
      nCtrPartVals := 1;
      
--      for colctr in 1 .. oTheSheetColumnInfo.count
--      loop     
--      
----        if oTheSheetColumnInfo(colctr).rptColTypeCode = 'DAILYPARTINV'
----        then
----            if ( vn_TmpGPInvQty < 0 AND vb_FirstNegativeDateSet = false  )
----              then vc_FirstNegativeDateText := ((to_char(oTheSheetColumnInfo(colctr).shipment_date,'DY DD-MON')));
----                   vb_FirstNegativeDateSet := true;
----                  EXIT;
----            end if;
----                   
----            if ( vn_TmpBPInvQty < 0 AND vb_FirstNegativeDateSet = false )
----                then vc_FirstNegativeDateText := ((to_char(oTheSheetColumnInfo(colctr).shipment_date,'DY DD-MON')));
----                     vb_FirstNegativeDateSet := true;
----                EXIT;
----            end if;    
----            
----        end if;
--      end loop;

--      vr_PrevPartRow := rec_CurrPartRow;
    
    END LOOP; 
    
RETURN vc_TotalEndInvNumber;   
EXCEPTION
WHEN OTHERS THEN
   raise_application_error(-20001,'An error was encountered - '||SQLCODE||' -ERROR- '||SQLERRM);
END;
-- ------------------------------------------------------------------------------------------------------------------------------
-- ------------------------------------------------------------------------------------------------------------------------------

PROCEDURE printsection( sectionorder IN number ) 
IS
    vc_PartName VARCHAR2(100);
BEGIN
    vb_PrevPartRowExists := FALSE;
    vc_PartName := ' ';
    
    FOR rec_CurrPartRow  IN
    (
      SELECT *
      FROM reco_rstx_tmpshpcalparts 
      WHERE 
           n_PartNumLen BETWEEN 4 AND 34        -- JNL 4.0
           AND sortorder = sectionorder
      ORDER BY  sortorder,          -- 1=S504 parts, 2=D504 parts, 3=s506, 4=d506, 5=AllOther parts
                g_partpunch,
                g_parttype,
                g_partnumlen
    )
    LOOP
    
      vc_PartName := rec_CurrPartRow.G_PARTNAME;
      vn_TmpNPInvQty := rec_CurrPartRow.n_originvqty;
      vn_TmpBPInvQty := rec_CurrPartRow.b_originvqty;
      vn_TmpGPInvQty := rec_CurrPartRow.g_originvqty;
      
      OPEN cur_ThisPartVals(rec_CurrPartRow.b_partid,
                            rec_CurrPartRow.g_partid);
      FETCH cur_ThisPartVals BULK COLLECT INTO oThisPartVals;
      CLOSE cur_ThisPartVals;
      
      nCtrPartVals := 1;
      
      vn_TmpDayCtr := 0;
      
      IF NOT bSummaryReport THEN
        FOR colctr IN 1 .. oTheSheetColumnInfo.count
        LOOP

          IF oTheSheetColumnInfo(colctr).rptColTypeCode = 'PARTNAME'
          THEN
            IF rec_CurrPartRow.sortorder = sectionorder
            THEN
              reco_web_functions.col_span := 1;
              reco_web_functions.cell_attr := vc_Color_InvText;
              reco_web_functions.add_data_column(rec_CurrPartRow.G_PARTNAME);  -- JNL
            ELSE
              reco_web_functions.col_span := 1;
              reco_web_functions.cell_attr := '';
              reco_web_functions.add_data_column(
                rec_CurrPartRow.g_partname);
            END IF;
                              
          ELSIF oTheSheetColumnInfo(colctr).rptColTypeCode = 'DAILYPARTINV'
          THEN
            vn_TmpDayCtr := vn_TmpDayCtr + 1;
            
            IF oTheSheetColumnInfo(colctr).num_child_cols = 3
            THEN
              reco_web_functions.col_span := 1;
              reco_web_functions.cell_attr := vc_Color_OddDayNorm;
              IF MOD(vn_TmpDayCtr,2) = 0
              THEN reco_web_functions.cell_attr := vc_Color_EvenDayNorm;
              END IF;
              IF vn_TmpNPInvQty < 0
                THEN reco_web_functions.cell_attr := vc_Color_Negative;
              END IF;
              reco_web_functions.add_data_column(TO_CHAR(vn_TmpNPInvQty));
            END IF;
            
            reco_web_functions.col_span := 1;
            reco_web_functions.cell_attr := vc_Color_OddDayNorm;
            IF MOD(vn_TmpDayCtr,2) = 0
              THEN reco_web_functions.cell_attr := vc_Color_EvenDayNorm;
            END IF;
            IF vn_TmpBPInvQty < 0
              THEN reco_web_functions.cell_attr := vc_Color_Negative;
            END IF;
            reco_web_functions.add_data_column(TO_CHAR(vn_TmpBPInvQty));
            
            reco_web_functions.col_span := 1;
            reco_web_functions.cell_attr := vc_Color_OddDayNorm;
            IF MOD(vn_TmpDayCtr,2) = 0
              THEN reco_web_functions.cell_attr := vc_Color_EvenDayNorm;
            END IF;
            
            IF vn_TmpGPInvQty < 0
              THEN reco_web_functions.cell_attr := vc_Color_Negative;
            END IF;
            reco_web_functions.add_data_column(TO_CHAR(vn_TmpGPInvQty));
                 
          ELSIF oTheSheetColumnInfo(colctr).rptColTypeCode = 'DELIVEREDSHIP'
          THEN
            IF nCtrPartVals <= oThisPartVals.count
            AND oThisPartVals(nCtrPartVals).shipment_id =
                  oTheSheetColumnInfo(colctr).shipment_id
            THEN
              IF oThisPartVals(nCtrPartVals).totblack = 0
              THEN
                reco_web_functions.col_span := 1;
                reco_web_functions.cell_attr := vc_Color_DelivStdTxt;
                reco_web_functions.add_data_column(' ');
              ELSIF oThisPartVals(nCtrPartVals).totblack != 0
              THEN
                reco_web_functions.col_span := 1;
                reco_web_functions.cell_attr := vc_Color_BlackSteel;
                reco_web_functions.add_data_column(
                  TO_CHAR(oThisPartVals(nCtrPartVals).totblack));
  --              vn_TmpBPInvQty := vn_TmpBPInvQty -
  --                oThisPartVals(nCtrPartVals).totblack;
              END IF;
              
              IF oThisPartVals(nCtrPartVals).totgalv = 0
              THEN
                reco_web_functions.col_span := 1;
                reco_web_functions.cell_attr := vc_Color_DelivStdTxt;
                reco_web_functions.add_data_column(' ');
              ELSIF oThisPartVals(nCtrPartVals).totgalv != 0
              THEN
                reco_web_functions.col_span := 1;
                reco_web_functions.cell_attr := vc_Color_DelivStdTxt;
                reco_web_functions.add_data_column(
                  TO_CHAR(oThisPartVals(nCtrPartVals).totgalv));
  --              vn_TmpGPInvQty := vn_TmpGPInvQty -
  --                oThisPartVals(nCtrPartVals).totgalv;
              END IF;
              
              nCtrPartVals := nCtrPartVals + 1;
            ELSE
              reco_web_functions.col_span := 1;
              reco_web_functions.cell_attr := vc_Color_DelivStdTxt;
              reco_web_functions.add_data_column(' ');
              reco_web_functions.add_data_column(' ');
            END IF;
          ELSIF oTheSheetColumnInfo(colctr).rptColTypeCode = 'PENDINGSHIP'
          THEN
            IF nCtrPartVals <= oThisPartVals.count
            AND oThisPartVals(nCtrPartVals).shipment_id =
                  oTheSheetColumnInfo(colctr).shipment_id
            THEN
              IF oThisPartVals(nCtrPartVals).totblack = 0
              THEN
                reco_web_functions.col_span := 1;
                reco_web_functions.cell_attr := vc_Color_OddDayNorm;
                IF MOD(vn_TmpDayCtr,2) = 0
                THEN reco_web_functions.cell_attr := vc_Color_EvenDayNorm;
                END IF;
                reco_web_functions.add_data_column(' ');
              ELSIF oThisPartVals(nCtrPartVals).totblack != 0
              THEN
                reco_web_functions.col_span := 1;
                reco_web_functions.cell_attr := vc_Color_BlackSteel;
                reco_web_functions.add_data_column(
                  TO_CHAR(oThisPartVals(nCtrPartVals).totblack));
                vn_TmpBPInvQty := vn_TmpBPInvQty -
                  oThisPartVals(nCtrPartVals).totblack;
              END IF;
              
              IF oThisPartVals(nCtrPartVals).totgalv = 0
              THEN
                reco_web_functions.col_span := 1;
                reco_web_functions.cell_attr := vc_Color_OddDayNorm;
                IF MOD(vn_TmpDayCtr,2) = 0
                THEN reco_web_functions.cell_attr := vc_Color_EvenDayNorm;
                END IF;
                reco_web_functions.add_data_column(' ');
              ELSIF oThisPartVals(nCtrPartVals).totgalv != 0
              THEN
                reco_web_functions.col_span := 1;
                reco_web_functions.cell_attr := vc_Color_OddDayNorm;
                IF MOD(vn_TmpDayCtr,2) = 0
                THEN reco_web_functions.cell_attr := vc_Color_EvenDayNorm;
                END IF;
                
                reco_web_functions.add_data_column(
                  TO_CHAR(oThisPartVals(nCtrPartVals).totgalv));
                vn_TmpGPInvQty := vn_TmpGPInvQty -
                  oThisPartVals(nCtrPartVals).totgalv;
              END IF;
              
              nCtrPartVals := nCtrPartVals + 1;
            ELSE
              reco_web_functions.col_span := 1;
              reco_web_functions.cell_attr := vc_Color_OddDayNorm;
              IF MOD(vn_TmpDayCtr,2) = 0
              THEN reco_web_functions.cell_attr := vc_Color_EvenDayNorm;
              END IF;
              reco_web_functions.add_data_column(' ');
              reco_web_functions.add_data_column(' ');
            END IF;
            
          ELSIF oTheSheetColumnInfo(colctr).rptColTypeCode = 'DAYPARTPROPOSEDMFG'
          THEN
            DECLARE
              vn_NumberForCell number;
            BEGIN
              
              SELECT SUM(punrun.qty_bars_processed)
              INTO vn_NumberForCell
              FROM  reco_rstx_calday calday, -- Good:get_date_toshowin_rpt description
                    reco_rstx_punrun_hist punrun,
                    (
                      SELECT DISTINCT
                              subasg.punrun_id,
                              subreq.reqlength,
                              subreq.reqtype,
                              subreq.reqpunch
                      FROM  reco_rstx_punrun_hist subrun,
                            reco_rstx_punreq_hist subreq,
                            reco_rstx_punasg_hist subasg
                      WHERE   subrun.punrun_id = subasg.punrun_id
                      AND     subasg.punreq_id = subreq.punreq_id
                      AND     subrun.cutsch_hist_id = vn_WorkingHistId
                      AND     subasg.cutsch_hist_id = vn_WorkingHistId
                      AND     subreq.cutsch_hist_id = vn_WorkingHistId
                    ) subQPartData
              WHERE   oTheSheetColumnInfo(colctr).shipment_date = calday.thedate
              AND     calday.calday_id = punrun.calday_id
              AND     punrun.cutsch_hist_id = vn_WorkingHistId
              AND     punrun.punrun_id = subQPartData.punrun_id
              AND     subQPartData.reqlength =
                                  rec_CurrPartRow.b_partnumlen
              AND     subQPartData.reqtype =
                                  rec_CurrPartRow.b_parttype
              AND     subQPartData.reqpunch =
                                  rec_CurrPartRow.b_partpunch;
              --NOTE: We do not care about PunchSch coating
              --      because for this report we label all
              --      punching results as black pieces
              
              vn_NumberForCell := NVL(vn_NumberForCell,0);
              
              reco_web_functions.col_span := 1;
              reco_web_functions.cell_attr := vc_Color_OddDayNorm;
              IF MOD(vn_TmpDayCtr,2) = 0
              THEN reco_web_functions.cell_attr := vc_Color_EvenDayNorm;
              END IF;
              IF vn_NumberForCell = 0
              THEN reco_web_functions.add_data_column(' ');
              ELSIF vn_NumberForCell != 0
              THEN reco_web_functions.add_data_column(TO_CHAR(vn_NumberForCell));
              END IF;
              
              vn_TmpBPInvQty := vn_TmpBPInvQty + vn_NumberForCell;
            END;
          
          ELSIF oTheSheetColumnInfo(colctr).rptColTypeCode = 'ENDINVTOTAL'
          THEN
            vn_TmpDayCtr := vn_TmpDayCtr + 1;
            
            reco_web_functions.col_span := 1;
            reco_web_functions.cell_attr := '';
            reco_web_functions.add_data_column(TO_CHAR(vn_TmpBPInvQty));
            
            reco_web_functions.col_span := 1;
            reco_web_functions.cell_attr := '';
            reco_web_functions.add_data_column(TO_CHAR(vn_TmpGPInvQty));
            
         ELSIF oTheSheetColumnInfo(colctr).rptColTypeCode = 'NEGATIVEINV'
          THEN
                      
            reco_web_functions.col_span := 2;
            reco_web_functions.cell_attr := vc_Color_Negative;
            reco_web_functions.add_data_column(getFirstNegativeDateText(sectionorder, vc_PartName));
  
          END IF;
        END LOOP;
      
      ELSIF bSummaryReport THEN
      -- JNL REPORTING CONDITION START
      ----------------------------------------------------------------------------------------------------------------
      ----------------------------------------------------------------------------------------------------------------
        FOR colctr IN 1 .. oTheSheetColumnInfo.count
        LOOP
          IF oTheSheetColumnInfo(colctr).rptColTypeCode = 'PARTNAME'
          THEN
            IF rec_CurrPartRow.sortorder = sectionorder
            THEN
              reco_web_functions.col_span := 1;
              reco_web_functions.cell_attr := vc_Color_InvText;
              reco_web_functions.add_data_column(rec_CurrPartRow.G_PARTNAME);  -- JNL
            ELSE
              reco_web_functions.col_span := 1;
              reco_web_functions.cell_attr := '';
              reco_web_functions.add_data_column(
                rec_CurrPartRow.g_partname);
            END IF;
                              
          ELSIF oTheSheetColumnInfo(colctr).rptColTypeCode = 'DAILYPARTINV'
          THEN
            vn_TmpDayCtr := vn_TmpDayCtr + 1;
            
            IF oTheSheetColumnInfo(colctr).num_child_cols = 3
            THEN
              reco_web_functions.col_span := 1;
              reco_web_functions.cell_attr := vc_Color_OddDayNorm;
              IF MOD(vn_TmpDayCtr,2) = 0
              THEN reco_web_functions.cell_attr := vc_Color_EvenDayNorm;
              END IF;
              IF vn_TmpNPInvQty < 0
                THEN reco_web_functions.cell_attr := vc_Color_Negative;
              END IF;
              
              -- JNL REPORT IF CONDITION
              IF colctr = 2 OR colctr = (oTheSheetColumnInfo.count ) OR colctr = (oTheSheetColumnInfo.count - 1) THEN
                reco_web_functions.add_data_column(TO_CHAR(vn_TmpNPInvQty));
              END IF;
                
            END IF;
            
            reco_web_functions.col_span := 1;
            reco_web_functions.cell_attr := vc_Color_OddDayNorm;
            IF MOD(vn_TmpDayCtr,2) = 0
              THEN reco_web_functions.cell_attr := vc_Color_EvenDayNorm;
            END IF;
            IF vn_TmpBPInvQty < 0
              THEN reco_web_functions.cell_attr := vc_Color_Negative;
            END IF;
            
            -- JNL REPORT IF CONDITION
            IF colctr = 2 OR colctr = (oTheSheetColumnInfo.count ) OR colctr = (oTheSheetColumnInfo.count - 1) THEN
              reco_web_functions.add_data_column(TO_CHAR(vn_TmpBPInvQty));
            END IF;
            
            reco_web_functions.col_span := 1;
            reco_web_functions.cell_attr := vc_Color_OddDayNorm;
            IF MOD(vn_TmpDayCtr,2) = 0
              THEN reco_web_functions.cell_attr := vc_Color_EvenDayNorm;
            END IF;
            
            IF vn_TmpGPInvQty < 0
              THEN reco_web_functions.cell_attr := vc_Color_Negative;
            END IF;
            
            -- JNL REPORT IF CONDITION
            IF colctr = 2 OR colctr = (oTheSheetColumnInfo.count ) OR colctr = (oTheSheetColumnInfo.count - 1) THEN
              reco_web_functions.add_data_column(TO_CHAR(vn_TmpGPInvQty));
            END IF;
            
          ELSIF oTheSheetColumnInfo(colctr).rptColTypeCode = 'DELIVEREDSHIP'
          THEN
            IF nCtrPartVals <= oThisPartVals.count
            AND oThisPartVals(nCtrPartVals).shipment_id =
                  oTheSheetColumnInfo(colctr).shipment_id
            THEN
              IF oThisPartVals(nCtrPartVals).totblack = 0
              THEN
                reco_web_functions.col_span := 1;
                reco_web_functions.cell_attr := vc_Color_DelivStdTxt;
                -- JNL REPORT IF CONDITION
                IF colctr = 2 OR colctr = (oTheSheetColumnInfo.count ) OR colctr = (oTheSheetColumnInfo.count - 1) THEN
                  reco_web_functions.add_data_column(' ');
                END IF;
              ELSIF oThisPartVals(nCtrPartVals).totblack != 0
              THEN
                reco_web_functions.col_span := 1;
                reco_web_functions.cell_attr := vc_Color_BlackSteel;
                 -- JNL REPORT IF CONDITION
                IF colctr = 2 OR colctr = (oTheSheetColumnInfo.count ) OR colctr = (oTheSheetColumnInfo.count - 1) THEN
                  reco_web_functions.add_data_column(
                  TO_CHAR(oThisPartVals(nCtrPartVals).totblack));
                END IF;
                
  --              vn_TmpBPInvQty := vn_TmpBPInvQty -
  --                oThisPartVals(nCtrPartVals).totblack;
              END IF;
              
              IF oThisPartVals(nCtrPartVals).totgalv = 0
              THEN
                reco_web_functions.col_span := 1;
                reco_web_functions.cell_attr := vc_Color_DelivStdTxt;
                -- JNL REPORT IF CONDITION
                IF colctr = 2 OR colctr = (oTheSheetColumnInfo.count ) OR colctr = (oTheSheetColumnInfo.count - 1) THEN
                 reco_web_functions.add_data_column(' ');
                END IF;
                
                
              ELSIF oThisPartVals(nCtrPartVals).totgalv != 0
              THEN
                reco_web_functions.col_span := 1;
                reco_web_functions.cell_attr := vc_Color_DelivStdTxt;
                -- JNL REPORT IF CONDITION
                IF colctr = 2 OR colctr = (oTheSheetColumnInfo.count ) OR colctr = (oTheSheetColumnInfo.count - 1) THEN
                 reco_web_functions.add_data_column(
                  TO_CHAR(oThisPartVals(nCtrPartVals).totgalv));
                END IF;
  
  --              vn_TmpGPInvQty := vn_TmpGPInvQty -
  --                oThisPartVals(nCtrPartVals).totgalv;
              END IF;
              
              nCtrPartVals := nCtrPartVals + 1;
            ELSE
              reco_web_functions.col_span := 1;
              reco_web_functions.cell_attr := vc_Color_DelivStdTxt;
              
               -- JNL REPORT IF CONDITION
                IF colctr = 2 OR colctr = (oTheSheetColumnInfo.count ) OR colctr = (oTheSheetColumnInfo.count - 1) THEN
                 reco_web_functions.add_data_column(' ');
                reco_web_functions.add_data_column(' ');
                END IF;
                
            END IF;
          ELSIF oTheSheetColumnInfo(colctr).rptColTypeCode = 'PENDINGSHIP'
          THEN
            IF nCtrPartVals <= oThisPartVals.count
            AND oThisPartVals(nCtrPartVals).shipment_id =
                  oTheSheetColumnInfo(colctr).shipment_id
            THEN

              IF oThisPartVals(nCtrPartVals).totblack = 0
              THEN
                reco_web_functions.col_span := 1;
                reco_web_functions.cell_attr := vc_Color_OddDayNorm;
                IF MOD(vn_TmpDayCtr,2) = 0
                THEN reco_web_functions.cell_attr := vc_Color_EvenDayNorm;
                END IF;
                
                -- JNL REPORT IF CONDITION
                IF colctr = 2 OR colctr = (oTheSheetColumnInfo.count ) OR colctr = (oTheSheetColumnInfo.count - 1) THEN
                reco_web_functions.add_data_column(' ');
                END IF;
                
              ELSIF oThisPartVals(nCtrPartVals).totblack != 0
              THEN
                reco_web_functions.col_span := 1;
                reco_web_functions.cell_attr := vc_Color_BlackSteel;
                
                -- JNL REPORT IF CONDITION
                IF colctr = 2 OR colctr = (oTheSheetColumnInfo.count ) OR colctr = (oTheSheetColumnInfo.count - 1) THEN
                reco_web_functions.add_data_column(
                  TO_CHAR(oThisPartVals(nCtrPartVals).totblack));
                END IF;
                
                
                vn_TmpBPInvQty := vn_TmpBPInvQty -
                  oThisPartVals(nCtrPartVals).totblack;
              END IF;
              
              IF oThisPartVals(nCtrPartVals).totgalv = 0
              THEN
                reco_web_functions.col_span := 1;
                reco_web_functions.cell_attr := vc_Color_OddDayNorm;
                IF MOD(vn_TmpDayCtr,2) = 0
                THEN reco_web_functions.cell_attr := vc_Color_EvenDayNorm;
                END IF;
                
                -- JNL REPORT IF CONDITION
                IF colctr = 2 OR colctr = (oTheSheetColumnInfo.count ) OR colctr = (oTheSheetColumnInfo.count - 1) THEN
                  reco_web_functions.add_data_column(' ');
                END IF;
                
                
              ELSIF oThisPartVals(nCtrPartVals).totgalv != 0
              THEN
                reco_web_functions.col_span := 1;
                reco_web_functions.cell_attr := vc_Color_OddDayNorm;
                IF MOD(vn_TmpDayCtr,2) = 0
                THEN reco_web_functions.cell_attr := vc_Color_EvenDayNorm;
                END IF;
                
                -- JNL REPORT IF CONDITION
                IF colctr = 2 OR colctr = (oTheSheetColumnInfo.count ) OR colctr = (oTheSheetColumnInfo.count - 1) THEN
                  reco_web_functions.add_data_column(
                  TO_CHAR(oThisPartVals(nCtrPartVals).totgalv));
                END IF;
                
                
                vn_TmpGPInvQty := vn_TmpGPInvQty -
                  oThisPartVals(nCtrPartVals).totgalv;
              END IF;
              
              nCtrPartVals := nCtrPartVals + 1;
            ELSE
              reco_web_functions.col_span := 1;
              reco_web_functions.cell_attr := vc_Color_OddDayNorm;
              IF MOD(vn_TmpDayCtr,2) = 0
              THEN reco_web_functions.cell_attr := vc_Color_EvenDayNorm;
              END IF;
              
                -- JNL REPORT IF CONDITION
                IF colctr = 2 OR colctr = (oTheSheetColumnInfo.count ) OR colctr = (oTheSheetColumnInfo.count - 1) THEN
                  reco_web_functions.add_data_column(' ');
                  reco_web_functions.add_data_column(' ');
                END IF;
                  
            END IF;
            
          ELSIF oTheSheetColumnInfo(colctr).rptColTypeCode = 'DAYPARTPROPOSEDMFG'
          THEN
            DECLARE
              vn_NumberForCell number;
            BEGIN
              
              SELECT SUM(punrun.qty_bars_processed)
              INTO vn_NumberForCell
              FROM  reco_rstx_calday calday, -- Good:get_date_toshowin_rpt description
                    reco_rstx_punrun_hist punrun,
                    (
                      SELECT DISTINCT
                              subasg.punrun_id,
                              subreq.reqlength,
                              subreq.reqtype,
                              subreq.reqpunch
                      FROM  reco_rstx_punrun_hist subrun,
                            reco_rstx_punreq_hist subreq,
                            reco_rstx_punasg_hist subasg
                      WHERE   subrun.punrun_id = subasg.punrun_id
                      AND     subasg.punreq_id = subreq.punreq_id
                      AND     subrun.cutsch_hist_id = vn_WorkingHistId
                      AND     subasg.cutsch_hist_id = vn_WorkingHistId
                      AND     subreq.cutsch_hist_id = vn_WorkingHistId
                    ) subQPartData
              WHERE   oTheSheetColumnInfo(colctr).shipment_date = calday.thedate
              AND     calday.calday_id = punrun.calday_id
              AND     punrun.cutsch_hist_id = vn_WorkingHistId
              AND     punrun.punrun_id = subQPartData.punrun_id
              AND     subQPartData.reqlength =
                                  rec_CurrPartRow.b_partnumlen
              AND     subQPartData.reqtype =
                                  rec_CurrPartRow.b_parttype
              AND     subQPartData.reqpunch =
                                  rec_CurrPartRow.b_partpunch;
              --NOTE: We do not care about PunchSch coating
              --      because for this report we label all
              --      punching results as black pieces
              
              vn_NumberForCell := NVL(vn_NumberForCell,0);
              
              reco_web_functions.col_span := 1;
              reco_web_functions.cell_attr := vc_Color_OddDayNorm;
              IF MOD(vn_TmpDayCtr,2) = 0
              THEN reco_web_functions.cell_attr := vc_Color_EvenDayNorm;
              END IF;
              IF vn_NumberForCell = 0
              THEN 
                -- JNL REPORT IF CONDITION
                IF colctr = 2 OR colctr = (oTheSheetColumnInfo.count ) OR colctr = (oTheSheetColumnInfo.count - 1) THEN
                  reco_web_functions.add_data_column(' ');
                END IF;
                
              ELSIF vn_NumberForCell != 0
              THEN 
                -- JNL REPORT IF CONDITION
                IF colctr = 2 OR colctr = (oTheSheetColumnInfo.count ) OR colctr = (oTheSheetColumnInfo.count - 1) THEN
                  reco_web_functions.add_data_column(TO_CHAR(vn_NumberForCell));
                END IF;
                
              END IF;
              
              vn_TmpBPInvQty := vn_TmpBPInvQty + vn_NumberForCell;
            END;  
          
          ELSIF oTheSheetColumnInfo(colctr).rptColTypeCode = 'ENDINVTOTAL'
          THEN
            vn_TmpDayCtr := vn_TmpDayCtr + 1;
            
            reco_web_functions.col_span := 1;
            reco_web_functions.cell_attr := '';
            
            -- JNL REPORT IF CONDITION
            IF colctr = (oTheSheetColumnInfo.count ) OR colctr = (oTheSheetColumnInfo.count - 1) THEN
              reco_web_functions.add_data_column(TO_CHAR(vn_TmpBPInvQty));
            END IF;
           
            reco_web_functions.col_span := 1;
            reco_web_functions.cell_attr := '';
            
            -- JNL REPORT IF CONDITION
            IF colctr = (oTheSheetColumnInfo.count ) OR colctr = (oTheSheetColumnInfo.count - 1) THEN
              reco_web_functions.add_data_column(TO_CHAR(vn_TmpGPInvQty));
            END IF;
            
         ELSIF oTheSheetColumnInfo(colctr).rptColTypeCode = 'NEGATIVEINV'
          THEN
                      
            reco_web_functions.col_span := 2;
            reco_web_functions.cell_attr := vc_Color_Negative;
            
            -- JNL REPORT IF CONDITION
            IF colctr = (oTheSheetColumnInfo.count )THEN
              reco_web_functions.add_data_column(getFirstNegativeDateText(sectionorder, vc_PartName));
          END IF;
          
          END IF;
        END LOOP;
      ----------------------------------------------------------------------------------------------------------------
      ----------------------------------------------------------------------------------------------------------------
      END IF;
      -- JNL REPORTING CONDITION END
      
      reco_web_functions.print_datarow;
      
      vb_PrevPartRowExists := TRUE;
      vr_PrevPartRow := rec_CurrPartRow;
    
    END LOOP; 
  
       IF sectionorder = 1 THEN proc_PrintTwoWeightsRowsSP('S504%');
    ELSIF sectionorder = 2 THEN proc_PrintTwoWeightsRowsSP('D504%'); 
    ELSIF sectionorder = 3 THEN proc_PrintTwoWeightsRowsSP('S506%'); 
    ELSIF sectionorder = 4 THEN proc_PrintTwoWeightsRowsSP('D506%');      
    ELSE proc_PrintTwoWeightsRowsSP('');
    END IF;
    
END;

    BEGIN -- Body - Print part rows
      IF NVL(fnd_global.org_id,-1) <> 0 THEN
        get_reco_organization('0');
        END IF;
      printsection(1);
      printsection(2);
      printsection(3);
      printsection(4);
      printsection(5);
    
    END; -- Body - Print part rows
  
  reco_web_Functions.close_spreadsheet;
  
EXCEPTION
 WHEN others
 THEN
   htp.tableclose;
   htp.print('Report Exception Condition:'||thelocation||'-'||sqlerrm|| -- CONTINUE HERE ADD TO OTHER FUNCTS
            ' Date:'||TO_CHAR(SYSDATE,'DD-MON-YYYY'));
   htp.htmlClose;
   
END; -- rstx_shipcal_rpt
--------------------------------------------------------------------------------
PROCEDURE mfg_reporting_hist_rpt
IS
BEGIN -- mfg_reporting_hist_rpt
  
  ---
  -- Prepare spreadsheet
  ---
  
  reco_web_functions.reset_sheet;
  reco_web_functions.table_attr := 'border="1" frame="border" rules="all"';
  reco_web_functions.open_spreadsheet;
  
  ---
  -- Print title and date
  ---
  
  reco_web_functions.clear_headers;
  
  reco_web_functions.col_span := 3;
  reco_web_functions.cell_attr := '';
  reco_web_functions.add_header_column(
      'Reporting History - Printed at '||
              TO_CHAR(SYSDATE,'HH:MIAM DD-MON-YYYY '));
  
  reco_web_functions.print_header;
  
  FOR rec_Line IN
    (
      SELECT  reporting_hist_id,
              TO_CHAR(thetime,'DD-MON-YYYY HH:MIAM') thetime,
              theusername,
              description
      FROM reco_rstx_reporting_hist
      ORDER BY reporting_hist_id desc
    )
  LOOP
    reco_web_functions.col_span := 1;
    reco_web_functions.cell_attr := '';
    reco_web_functions.add_data_column(rec_Line.thetime);
    reco_web_functions.add_data_column(rec_Line.theusername);
    reco_web_functions.add_data_column(rec_Line.description);
    
    reco_web_functions.print_datarow;
  END LOOP;
  
  reco_web_Functions.close_spreadsheet;
  
EXCEPTION
 WHEN others
 THEN
   htp.tableclose;
   htp.print('Report Exception Condition:'||sqlerrm|| -- CONTINUE HERE ADD TO OTHER FUNCTS
            ' Date:'||TO_CHAR(SYSDATE,'DD-MON-YYYY'));
   htp.htmlClose;
END; -- mfg_reporting_hist_rpt

--------------------------------------------------------------------------------
-- Package Constructor
BEGIN
  get_reco_organization('0');
  
  SELECT category_set_id INTO nCSetR
  FROM apps.mtl_category_sets_tl WHERE category_set_name = 'Raw Materials';
  
  SELECT category_set_id INTO nCSetN
  FROM apps.mtl_category_sets_tl WHERE category_set_name = 'RS NoPunch';
  
  SELECT category_set_id INTO nCSetB
  FROM apps.mtl_category_sets_tl WHERE category_set_name = 'RS Black';
  
  SELECT category_set_id INTO nCSetG
  FROM apps.mtl_category_sets_tl WHERE category_set_name = 'RS Galv';
END; -- package body
