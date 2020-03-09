--Hw 6
--Shan Deng, Maddie Keist, Nikhita Pendekanti

SET SERVEROUTPUT ON;



--Q1 [Add A ZipCode Column, Populate It, And Remove All Rows With A Null ZipCode]

--Creating ZipCode Column
Alter Table Street_Cleaning
Add ZipCode char(5);

--Adding in ZipCode Parameter
Update Street_Cleaning
Set ZipCode = 
                Case 
                  When Substr(Address, -9, 9) = '(Virtual)' Then SubStr(Address, -15, 5)           --Includes Addresses That Have Zip Codes But... 
                                                                                                   --... End With "Virtual" Instead Of The Zip Code 
                  When Regexp_Like(SubStr(Address, -5),'^[[:digit:]]{5}') Then SubStr(Address, -5) --The IsNumeric() Check For Oracle SQL
                  Else NULL
                End;

--Removing all rows with undetected Zip Code values
Delete 
From Street_Cleaning
Where ZipCode IS NULL;

--Test Code
/*
Select Address, ZipCode
From Street_Cleaning
--Where Address like '%(Virtual)'
Order By Zipcode desc
*/



--Q2 [Create A View Of Fecal Cleanups By Zip Code]

Create View RequestFreq_byZip
As
Select ZipCode, Count(CaseID) Request_Freq
From Street_Cleaning
Where Request_Type = 'Human Waste'
Group By ZipCode
Order By Request_Freq Desc;

--Test Code
/* 
Select * from RequestFreq_byZip
*/



--Q3 [Create Functions To Extract Coordinates From The Format (Longitude,Latitude)]

--Extract Latitude Coordinate
Create OR Replace Function Get_Lat
(
  GPS_Coordinate_param varchar2
)
Return number
AS
  Lat_var number(20,11);
Begin
  Lat_var:= To_Number(Substr(GPS_Coordinate_param, 2, INSTR(GPS_Coordinate_param, ',') - 2));
  Return Lat_var;
End;

--Extract Longitude Coordinate
Create OR Replace Function Get_Lon
(
  GPS_Coordinate_param varchar2
)
Return number
AS
  Lon_var number(20,11);
Begin
  Lon_var:= To_Number(Substr(GPS_Coordinate_param, INSTR(GPS_Coordinate_param, ',') + 2, length(GPS_Coordinate_param) - INSTR(GPS_Coordinate_param, ',')-2));
  Return Lon_var;
End;

--Test Code
/*
Declare
     GPS_Coordinate_var varchar2(255):='(37.77605168, -122.410395881)';
Begin
     DBMS_OUTPUT.put_line(Get_Lat(GPS_Coordinate_var));
     DBMS_OUTPUT.put_line(Get_Lon(GPS_Coordinate_var));    
End; 
*/



--Q4 [Create Functions To Measure Distance And Check If That Distance Is Within A Range]

--Determines Distance Between Two Points
CREATE OR REPLACE FUNCTION distance(
  Lat1_param NUMBER,
  Lon1_param NUMBER,
  Lat2_param NUMBER,
  Lon2_param NUMBER
                                  ) 
RETURN NUMBER 
IS
  --Earth Maths
  PlanetRadius NUMBER := 3963;
  DegToRad NUMBER := 57.29577951; 
 
BEGIN
-- Surface Distance Equation
RETURN
    (PlanetRadius*ACOS((sin(Lat1_param/DegToRad)*SIN(Lat2_param/DegToRad))+(COS(Lat1_param/DegToRad)*COS(Lat2_param/DegToRad)*COS(Lon2_param/DegToRad-Lon1_param/DegToRad))));  
END;


--Determines If Distance Is Within A Given Range
CREATE OR REPLACE FUNCTION JudgeProximity 
(
    Lat1 Number,
    Lon1 Number,
    Lat2 Number,
    Lon2 Number,
    Radius_param Number
)     
RETURN NUMBER 
IS
Begin
    If distance(Lat1,Lon1,Lat2,Lon2) <= Radius_param Then
        Return 1; 
    ELsIF distance(Lat1,Lon1,Lat2,Lon2) > Radius_param Then
        Return 0; 
    End If; 
End; 

--Test Script
/*
Declare 
    LatVal_1 Number:= 37.7677; 
    LonVal_1 Number:= -122.4122;
    LatVal_2 Number:= 37.7678; 
    LonVal_2 Number:= -122.4122;
    RadVal Number := 0.5; 
    DistanceVal Number; 
    Proximity Number;
    
Begin
    DistanceVal:= distance(LatVal_1,LonVal_1,LatVal_2,LonVal_2);
    DBMS_OUTPUT.put_line(round(DistanceVal,3));
    Proximity:= JudgeProximity(LatVal_1,LonVal_1,LatVal_2,LonVal_2,RadVal);
    DBMS_OUTPUT.put_line(Proximity);
End; 
*/



-- Q5 [Counts The Amount Of Previous Poop Occurances That Have Happened Within A Given Distance To A Restaurant]

Create or replace Procedure Poop_Score
(
    Restaurant_Name_Param varchar2, 
    Radius_to_Restaurant number
)
IS  
    --Creates The Mandatory Cursor To Loop Through Each Poop Instance Coordinate And Check Relevancy
    cursor PoopEvent_Cur IS
        Select CaseID, "POINT" as Coordinate
        From Street_Cleaning
        Where "POINT" Is Not Null
            And Request_Type = 'Human Waste' 
        ;
        
    event_row Street_Cleaning%ROWTYPE; --Used For Data Type Consistency
    
    Poop_Score_var number:= 0; --Initial Count For Poops
    Restaurant_Coordinates varchar2(255);
    Latitude_1 Number(20,11); 
    Longitude_1 Number(20,11);
    Poop_Coordinates varchar2(255); 
    Latitude_2 Number(20,11); 
    Longitude_2 Number(20,11);  
    
Begin
    
    --Determine The Coordinates Of The Business
    select distinct Business_Location 
    into Restaurant_Coordinates
    from Restaurant
    where Restaurant_Name_Param = Business_Name
        and Business_Location is not null;
    Latitude_1:= Get_Lat(Restaurant_Coordinates);
    Longitude_1:= Get_Lon(Restaurant_Coordinates);
    
    --Checks For How Many Poop Instances Have Occurred Within A Given Distance To That Business
    For event_row in PoopEvent_Cur Loop
        Poop_Coordinates:= event_row.Coordinate; 
        Latitude_2:= Get_Lat(event_row.Coordinate);
        Longitude_2:= Get_Lon(event_row.Coordinate);
        
        -- +1 To Poop Score For Each Relevant Instance
        If JudgeProximity(Latitude_1,Longitude_1,Latitude_2,Longitude_2,Radius_to_Restaurant) = 1 Then
            Poop_Score_var := Poop_Score_var+1; 
        End IF; 
    End Loop; 
    
    --Return Outputs Given Poop Score
    DBMS_OUTPUT.put_line(Poop_Score_var||' '||' times of historical request to clean poops within '||Radius_to_Restaurant||' miles around the restaurant.'); 
    IF Poop_Score_var >=100 Then 
        DBMS_OUTPUT.put_line('Watch out! Tons of poops!');
    End IF; 
    Exception
    When No_Data_Found Then 
        dbms_output.put_line('No Matches found for the Restaurant');
    When others Then
        dbms_output.put_line('Unexpected Error'); 
End; 



--Q6 [Test For Poop Score Procedure]

Exec Poop_Score ('UNIMART',.1);
Exec Poop_Score ('UNIMART',.5);

Exec Poop_Score ('Press Club',.1);
Exec Poop_Score ('Press Club',.5);

Exec Poop_Score ('CAFE PICARO',.1);
Exec Poop_Score ('CAFE PICARO',.5);

Exec Poop_Score ('ABC',.1);
Exec Poop_Score ('ABC',.5);


















