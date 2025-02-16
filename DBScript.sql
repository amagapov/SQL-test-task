CREATE TABLE [ComponentRel](
	[relID] [int] IDENTITY(1,1) NOT NULL,
	[compID] [int] NOT NULL,
	[parentID] [int] NOT NULL,
	[compNum] [int] NOT NULL,
 CONSTRAINT [PK_ComponentRel] PRIMARY KEY CLUSTERED 
(
	[relID] ASC
)WITH (PAD_INDEX  = OFF, STATISTICS_NORECOMPUTE  = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS  = ON, ALLOW_PAGE_LOCKS  = ON) ON [PRIMARY]
) ON [PRIMARY]
GO

CREATE TABLE [ComponentList](
	[componentID] [int] IDENTITY(1,1) NOT NULL,
	[cName] [varchar](50) NOT NULL,
 CONSTRAINT [PK_ComponentList] PRIMARY KEY CLUSTERED 
(
	[componentID] ASC
)WITH (PAD_INDEX  = OFF, STATISTICS_NORECOMPUTE  = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS  = ON, ALLOW_PAGE_LOCKS  = ON) ON [PRIMARY]
) ON [PRIMARY]
GO

CREATE PROCEDURE [Report]
	@relID int,
	@out_result VARCHAR(100) OUTPUT
AS
BEGIN
	DECLARE @rootLvl INT;
	DECLARE @T TABLE(relID INT,compID INT,lvl INT,num INT,parent INT);
	WITH cte AS 
	(SELECT relID,compID,parentID, 0 AS lvl, compNum FROM ComponentRel 
	WHERE relID = @relID
	UNION ALL
	SELECT ComponentRel.relID,ComponentRel.compID,ComponentRel.parentID, cte.lvl + 1 AS lvl, ComponentRel.compNum
	FROM ComponentRel INNER JOIN
		 cte ON ComponentRel.parentID = cte.relID)
	INSERT INTO @T(relID,compID,lvl,num,parent)
	SELECT relID,compID,lvl,compNum,parentID FROM cte;
--	SELECT @out_result = CAST(COUNT(*) AS VARCHAR) FROM @T;
	SELECT @rootLvl = MIN(lvl) FROM @T;
	SELECT l.cName as name, t.num as num
	FROM @T t INNER JOIN 
		 ComponentList l ON l.componentID = t.compID
	WHERE (NOT t.relID IN (SELECT parent FROM @T)) OR (t.lvl = @rootLvl)
	ORDER BY t.lvl;		
	SET @out_result = @@ROWCOUNT;
END
GO

CREATE PROCEDURE [RenameComponent]
	@newName VARCHAR(50),
	@relID INT,
	@out_result VARCHAR(100) OUTPUT
AS
BEGIN
	SET @out_result = '0';
	DECLARE @cnt INT;
	BEGIN TRY
		BEGIN TRAN
			SELECT @cnt = COUNT(*) FROM ComponentList WHERE cName = @newName;
			IF @cnt = 0
				UPDATE ComponentList
				SET cName = @newName
				WHERE componentID = (SELECT compID FROM ComponentRel WHERE relID = @relID);
			IF @cnt > 0
				SET @out_result = 'nameExists';
		COMMIT TRAN
	END TRY	
	BEGIN CATCH
		IF @@TRANCOUNT > 0
		BEGIN
			SET @out_result = ERROR_MESSAGE()
			ROLLBACK TRAN
		END
	END CATCH
END
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [DeleteComponent]
	@relID int,
	@out_result VARCHAR(100) OUTPUT
AS
BEGIN
	BEGIN TRY
		BEGIN TRAN
			DECLARE @T TABLE(relID INT,compID INT,lvl INT);
			DECLARE @compID INT;			
			DECLARE @crCompID INT;
			DECLARE @crRelID INT;
			DECLARE @crLvl INT;
			DECLARE @cnt INT;
			SELECT @compID = compID FROM ComponentRel WHERE relID = @relID;
			WITH cte AS 
			(SELECT relID,compID,parentID, 0 AS lvl FROM ComponentRel 
			WHERE relID = @relID
			UNION ALL
			SELECT ComponentRel.relID,ComponentRel.compID,ComponentRel.parentID, cte.lvl + 1 AS lvl 
			FROM ComponentRel INNER JOIN
			     cte ON ComponentRel.parentID = cte.relID)
			INSERT INTO @T(relID,compID,lvl)
			SELECT relID,compID,lvl FROM cte
			DECLARE cur CURSOR FOR SELECT * FROM @T ORDER BY lvl DESC;
			OPEN cur;
			FETCH NEXT FROM cur INTO @crRelID,@crCompID,@crLvl;
			WHILE @@FETCH_STATUS = 0
			BEGIN
				IF NOT (EXISTS (SELECT * FROM ComponentRel WHERE compID = @crCompID AND relID <> @crRelID))
					BEGIN
						DELETE FROM ComponentRel WHERE relID = @crRelID;
						DELETE FROM ComponentList WHERE componentID = @crCompID;
					END;
				ELSE
					DELETE FROM ComponentRel WHERE relID = @crRelID;
				FETCH NEXT FROM cur INTO @crRelID,@crCompID,@crLvl;
			END;
			CLOSE cur;
		COMMIT TRAN
		SET @out_result = '0';
	END TRY	
	BEGIN CATCH
		IF @@TRANCOUNT > 0
		BEGIN
			SET @out_result = ERROR_MESSAGE()
			ROLLBACK TRAN
		END
	END CATCH

END
GO

CREATE PROCEDURE [AddComponent] 
	@componentName VARCHAR(50),
	@compNum INT = 1,
	@parentID INT = 0,
	@out_result VARCHAR(100) OUTPUT	
AS
BEGIN
	DECLARE @cnt INT;
	DECLARE @lastID INT;
	DECLARE @T TABLE(compID INT);
	BEGIN TRY
		BEGIN TRAN
			SELECT @cnt = COUNT(*) FROM ComponentList WHERE cName = @componentName;
			IF @cnt = 0
			BEGIN
				INSERT ComponentList (cName) VALUES (@componentName);
				SELECT @lastID = @@IDENTITY;
				INSERT ComponentRel (compID, parentID, compNum) VALUES (@lastID,@parentID,@compNum);
				SET @out_result = CAST(@lastID AS VARCHAR);
			END;	
			IF @cnt = 1
			BEGIN
				SELECT @lastID = componentID FROM ComponentList WHERE cName = @componentName;
				WITH cte AS 
				(SELECT relID,compID,parentID FROM ComponentRel 
				 WHERE relID = @parentID
				 UNION ALL
				 SELECT ComponentRel.relID,ComponentRel.compID,ComponentRel.parentID
				 FROM ComponentRel INNER JOIN
					  cte ON ComponentRel.relID = cte.parentID)
				INSERT INTO @T(compID)
				SELECT compID FROM cte;
				IF (NOT @lastID IN (SELECT compID FROM @T))
				BEGIN
					IF EXISTS (SELECT * FROM ComponentRel WHERE compID = @lastID AND parentID = @parentID AND parentID <> 0)
						UPDATE ComponentRel
						SET compNum = compNum + @compNum
						WHERE compID = @lastID AND parentID = @parentID AND parentID <> 0
					ELSE
						INSERT ComponentRel (compID, parentID, compNum) VALUES (@lastID,@parentID,@compNum);
					SET @out_result = CAST(@lastID AS VARCHAR);
				END
				ELSE	
				SET @out_result = 'Logical error: trying to recursively attach components';
			END;
			IF @cnt > 1
				SET @out_result = 'Database error: too many records for this component';
		COMMIT TRAN
	END TRY	
	BEGIN CATCH
		IF @@TRANCOUNT > 0
		BEGIN
			SET @out_result = ERROR_MESSAGE()
			ROLLBACK TRAN
		END
	END CATCH
END
GO

CREATE PROCEDURE [SelectComponentByParent]
@parentID INT = 0
AS
BEGIN
	SELECT l.cName AS name, r.relID AS ID, r.compNum as num
	FROM ComponentRel r INNER JOIN
         ComponentList l ON l.componentID = r.compID
	WHERE r.parentID = @parentID
END
GO
