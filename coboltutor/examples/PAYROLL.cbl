      *================================================================*
      * PAYROLL - Weekly payroll report (CobolTutor sample program)    *
      *                                                                *
      * Computes gross pay (with time-and-a-half overtime past 40      *
      * hours), a flat tax based on a simple bracket, and net pay for  *
      * a small table of employees, then prints a report with totals.  *
      *                                                                *
      * The employee data is built into the program, so no input files *
      * are needed. Written in fixed format for IBM Enterprise COBOL;  *
      * also compiles with GnuCOBOL:  cobc -x -std=ibm PAYROLL.cbl     *
      *================================================================*
       IDENTIFICATION DIVISION.
       PROGRAM-ID. PAYROLL.

       ENVIRONMENT DIVISION.

       DATA DIVISION.
       WORKING-STORAGE SECTION.

      *----------------------------------------------------------------*
      * Employee data: 5 records of 32 characters each.                *
      *   cols  1-4   employee id                                      *
      *   cols  5-24  name                                             *
      *   cols 25-29  hourly rate, 2 implied decimals (02550 = 25.50)  *
      *   cols 30-32  hours worked, 1 implied decimal (450 = 45.0)     *
      *----------------------------------------------------------------*
       01  EMPLOYEE-DATA.
           05  FILLER  PIC X(32)
               VALUE "1001ALICE JOHNSON       02550450".
           05  FILLER  PIC X(32)
               VALUE "1002BOB MARTINEZ        01875380".
           05  FILLER  PIC X(32)
               VALUE "1003CAROL NGUYEN        04200400".
           05  FILLER  PIC X(32)
               VALUE "1004DAVID OKAFOR        03120500".
           05  FILLER  PIC X(32)
               VALUE "1005EMMA SCHULTZ        01500225".

      * The same storage viewed as a table of fields.
       01  EMPLOYEE-TABLE REDEFINES EMPLOYEE-DATA.
           05  EMPLOYEE OCCURS 5 TIMES INDEXED BY EMP-IDX.
               10  EMP-ID              PIC 9(4).
               10  EMP-NAME            PIC X(20).
               10  EMP-RATE            PIC 9(3)V99.
               10  EMP-HOURS           PIC 9(2)V9.

      * Constants.
       01  WS-EMPLOYEE-COUNT           PIC 9(2)      VALUE 5.
       01  WS-STANDARD-HOURS           PIC 9(2)V9    VALUE 40.0.
       01  WS-OT-MULTIPLIER            PIC 9V9       VALUE 1.5.

      * Work fields for one employee (packed decimal for arithmetic).
       01  WS-CALC.
           05  WS-REGULAR-HOURS        PIC 9(2)V9    COMP-3.
           05  WS-OVERTIME-HOURS       PIC 9(2)V9    COMP-3.
           05  WS-GROSS                PIC 9(6)V99   COMP-3.
           05  WS-TAX-RATE             PIC V99       COMP-3.
           05  WS-TAX                  PIC 9(6)V99   COMP-3.
           05  WS-NET                  PIC 9(6)V99   COMP-3.

      * Running totals for the report footer.
       01  WS-TOTALS.
           05  WS-TOTAL-GROSS          PIC 9(7)V99   COMP-3 VALUE 0.
           05  WS-TOTAL-TAX            PIC 9(7)V99   COMP-3 VALUE 0.
           05  WS-TOTAL-NET            PIC 9(7)V99   COMP-3 VALUE 0.

      *----------------------------------------------------------------*
      * Report lines. Edited PICTUREs (Z, comma, period) format the    *
      * numbers for display: leading zeros become spaces.              *
      *----------------------------------------------------------------*
       01  HEADER-LINE.
           05  FILLER  PIC X(26)  VALUE "ID    NAME".
           05  FILLER  PIC X(5)   VALUE "HOURS".
           05  FILLER  PIC X(12)  VALUE "       GROSS".
           05  FILLER  PIC X(12)  VALUE "         TAX".
           05  FILLER  PIC X(12)  VALUE "         NET".

       01  RULE-LINE                   PIC X(67)     VALUE ALL "-".

       01  DETAIL-LINE.
           05  DL-ID                   PIC 9(4).
           05  FILLER                  PIC X(2)      VALUE SPACES.
           05  DL-NAME                 PIC X(20).
           05  FILLER                  PIC X(1)      VALUE SPACES.
           05  DL-HOURS                PIC Z9.9.
           05  FILLER                  PIC X(2)      VALUE SPACES.
           05  DL-GROSS                PIC ZZZ,ZZ9.99.
           05  FILLER                  PIC X(2)      VALUE SPACES.
           05  DL-TAX                  PIC ZZZ,ZZ9.99.
           05  FILLER                  PIC X(2)      VALUE SPACES.
           05  DL-NET                  PIC ZZZ,ZZ9.99.

       01  TOTAL-LINE.
           05  FILLER                  PIC X(33)     VALUE "TOTALS".
           05  TL-GROSS                PIC ZZZ,ZZ9.99.
           05  FILLER                  PIC X(2)      VALUE SPACES.
           05  TL-TAX                  PIC ZZZ,ZZ9.99.
           05  FILLER                  PIC X(2)      VALUE SPACES.
           05  TL-NET                  PIC ZZZ,ZZ9.99.

       PROCEDURE DIVISION.
      *----------------------------------------------------------------*
      * Main control: header, one detail line per employee, totals.    *
      *----------------------------------------------------------------*
       0000-MAIN.
           PERFORM 1000-PRINT-HEADER
           PERFORM 2000-PROCESS-EMPLOYEE
               VARYING EMP-IDX FROM 1 BY 1
               UNTIL EMP-IDX > WS-EMPLOYEE-COUNT
           PERFORM 3000-PRINT-TOTALS
           STOP RUN.

       1000-PRINT-HEADER.
           DISPLAY "WEEKLY PAYROLL REPORT"
           DISPLAY RULE-LINE
           DISPLAY HEADER-LINE
           DISPLAY RULE-LINE.

      *----------------------------------------------------------------*
      * Pay calculation for the employee at EMP-IDX.                   *
      *----------------------------------------------------------------*
       2000-PROCESS-EMPLOYEE.
      *    Split hours into regular and overtime.
           IF EMP-HOURS (EMP-IDX) > WS-STANDARD-HOURS
               MOVE WS-STANDARD-HOURS TO WS-REGULAR-HOURS
               COMPUTE WS-OVERTIME-HOURS =
                   EMP-HOURS (EMP-IDX) - WS-STANDARD-HOURS
           ELSE
               MOVE EMP-HOURS (EMP-IDX) TO WS-REGULAR-HOURS
               MOVE ZERO TO WS-OVERTIME-HOURS
           END-IF

      *    Overtime hours are paid at 1.5 times the hourly rate.
           COMPUTE WS-GROSS ROUNDED =
               (WS-REGULAR-HOURS * EMP-RATE (EMP-IDX))
             + (WS-OVERTIME-HOURS * EMP-RATE (EMP-IDX)
                                  * WS-OT-MULTIPLIER)

      *    Pick a flat tax rate from the gross-pay bracket.
           EVALUATE TRUE
               WHEN WS-GROSS > 1500
                   MOVE 0.22 TO WS-TAX-RATE
               WHEN WS-GROSS > 800
                   MOVE 0.15 TO WS-TAX-RATE
               WHEN OTHER
                   MOVE 0.10 TO WS-TAX-RATE
           END-EVALUATE

           COMPUTE WS-TAX ROUNDED = WS-GROSS * WS-TAX-RATE
           SUBTRACT WS-TAX FROM WS-GROSS GIVING WS-NET

           ADD WS-GROSS TO WS-TOTAL-GROSS
           ADD WS-TAX   TO WS-TOTAL-TAX
           ADD WS-NET   TO WS-TOTAL-NET

           MOVE EMP-ID (EMP-IDX)    TO DL-ID
           MOVE EMP-NAME (EMP-IDX)  TO DL-NAME
           MOVE EMP-HOURS (EMP-IDX) TO DL-HOURS
           MOVE WS-GROSS            TO DL-GROSS
           MOVE WS-TAX              TO DL-TAX
           MOVE WS-NET              TO DL-NET
           DISPLAY DETAIL-LINE.

       3000-PRINT-TOTALS.
           MOVE WS-TOTAL-GROSS TO TL-GROSS
           MOVE WS-TOTAL-TAX   TO TL-TAX
           MOVE WS-TOTAL-NET   TO TL-NET
           DISPLAY RULE-LINE
           DISPLAY TOTAL-LINE.
