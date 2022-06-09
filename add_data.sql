--create database accounting;
--drop database accounting;
/*

Содержание скрипта:
	-Создание схем
	
	-Создание роли и пользователя
	users
	jun_user
	
	-Таблицы и представления
	src.consignment
	src.employees_list
	src.items_list
	src.property_list
	src.v_property_list
	src.v_statistic
	
	-Последовательность
	src.property_list_inventory_number_seq

	-Вставки строк в вышеуказанные таблицы
	
	-Функции
	src.give_equipment	
	src.take_equipment

Раздача прав пользователю
*/

drop schema if exists src cascade;
drop schema if exists archive cascade;

create schema src;
create schema archive;

drop role if exists users;
drop role if exists jun_user;

--Создание роли Юзеров с правом наследования и ограниченным сроком действия пароля
CREATE ROLE users WITH 
	NOSUPERUSER
	NOCREATEDB
	NOCREATEROLE
	INHERIT
	NOLOGIN
	NOREPLICATION
	NOBYPASSRLS
	CONNECTION LIMIT -1
	VALID UNTIL '2022-12-01';

create user jun_user with 
	NOSUPERUSER
	NOCREATEDB
	NOCREATEROLE
	INHERIT
	LOGIN
	NOREPLICATION
	NOBYPASSRLS
	CONNECTION LIMIT -1
	password 'abracadabra24'
	VALID UNTIL '2022-12-01';

--Пригласить в группу пользователя
grant users to jun_user;


-- src.consignment
CREATE TABLE src.consignment (
	consignment_id int8 NOT NULL GENERATED ALWAYS AS IDENTITY,
	number_consignment varchar NOT NULL DEFAULT ''::character varying, -- номер накладной, состоит из букв и цифр
	receipt_date date NOT NULL DEFAULT now(), -- дата поступления
	CONSTRAINT consignment_pkey PRIMARY KEY (consignment_id)
);
COMMENT ON TABLE src.consignment IS 'consignment - таблица, в которой хранится документация накладных и дат поступления';

-- Column comments
COMMENT ON COLUMN src.consignment.number_consignment IS 'номер накладной, состоит из букв и цифр';
COMMENT ON COLUMN src.consignment.receipt_date IS 'дата поступления';

-- Permissions
ALTER TABLE src.consignment OWNER TO postgres;
GRANT ALL ON TABLE src.consignment TO postgres;
GRANT SELECT ON TABLE src.consignment TO users;


-- src.employees_list
CREATE TABLE src.employees_list (
	employee_id int8 NOT NULL GENERATED ALWAYS AS IDENTITY,
	full_name varchar NOT NULL, -- полное имя сотрудника
	birth_date date NULL,
	department varchar NOT NULL DEFAULT 'Иное'::character varying, -- название отдела, в котором работает сотрудник
	CONSTRAINT employees_list_pkey PRIMARY KEY (employee_id),
	UNIQUE (full_name, birth_date, department)
);
COMMENT ON TABLE src.employees_list IS 'employees_list - список сотрудников';

-- Column comments
COMMENT ON COLUMN src.employees_list.full_name IS 'полное имя сотрудника';
COMMENT ON COLUMN src.employees_list.department IS 'название отдела, в котором работает сотрудник';

-- Permissions
ALTER TABLE src.employees_list OWNER TO postgres;
GRANT ALL ON TABLE src.employees_list TO postgres;
GRANT INSERT, SELECT, UPDATE ON TABLE src.employees_list TO users;


-- src.items_list
CREATE TABLE src.items_list (
	items_id int8 NOT NULL GENERATED ALWAYS AS IDENTITY,
	title varchar NOT NULL UNIQUE, -- название техники
	CONSTRAINT items_list_pkey PRIMARY KEY (items_id)
);
COMMENT ON TABLE src.items_list IS 'items_list - список возможной техники для вставки в property_list';

-- Column comments
COMMENT ON COLUMN src.items_list.title IS 'название техники';

-- Permissions
ALTER TABLE src.items_list OWNER TO postgres;
GRANT ALL ON TABLE src.items_list TO postgres;
GRANT INSERT, SELECT, UPDATE ON TABLE src.items_list TO users;


-- src.property_list_inventory_number_seq
CREATE SEQUENCE src.property_list_inventory_number_seq
	INCREMENT BY 1
	MINVALUE 1
	MAXVALUE 9223372036854775807
	START 1
	CACHE 1
	NO CYCLE;

-- Permissions
ALTER SEQUENCE src.property_list_inventory_number_seq OWNER TO postgres;
GRANT ALL ON SEQUENCE src.property_list_inventory_number_seq TO postgres;
GRANT ALL ON SEQUENCE src.property_list_inventory_number_seq TO users;

-- src.property_list
CREATE TABLE src.property_list (
	property_id int8 NOT NULL GENERATED ALWAYS AS IDENTITY,
	items_id int8 NOT NULL, -- ссылка на items_list - ID техники
	consignment_id int8 NOT NULL, -- ссылка на consignment - ID накладной
	inventory_number int8 not null default nextval('src.property_list_inventory_number_seq'), -- inventory_number - инвентарный номер. Для нумерация используется последовательность
	employee_owner int8 NULL, -- ссылка на employee_list - ID сотрудника, который закреплен за техникой
	state int8 NOT NULL DEFAULT 1, -- ID состояния техники: 1 - свободно, 2 - занято, 3 - в ремонте, 4 - списано
	CONSTRAINT property_list_pkey PRIMARY KEY (property_id),
	CONSTRAINT property_list_consignment_id_fkey FOREIGN KEY (consignment_id) REFERENCES src.consignment(consignment_id),
	CONSTRAINT property_list_employee_owner_fkey FOREIGN KEY (employee_owner) REFERENCES src.employees_list(employee_id),
	CONSTRAINT property_list_items_id_fkey FOREIGN KEY (items_id) REFERENCES src.items_list(items_id)
);
COMMENT ON TABLE src.property_list IS 'property_list - список техники, которая была проведена по накладной и числится в компании';

-- Column comments
COMMENT ON COLUMN src.property_list.items_id IS 'ссылка на items_list - ID техники';
COMMENT ON COLUMN src.property_list.consignment_id IS 'ссылка на consignment - ID накладной';
COMMENT ON COLUMN src.property_list.inventory_number IS 'inventory_number - инвентарный номер. Для нумерация используется последовательность';
COMMENT ON COLUMN src.property_list.employee_owner IS 'ссылка на employee_list - ID сотрудника, который закреплен за техникой';
COMMENT ON COLUMN src.property_list.state IS 'ID состояния техники: 1 - свободно, 2 - занято, 3 - в ремонте, 4 - списано';

-- Permissions
ALTER TABLE src.property_list OWNER TO postgres;
GRANT ALL ON TABLE src.property_list TO postgres;
GRANT INSERT, SELECT, UPDATE ON TABLE src.property_list TO users;


-- src.v_property_list source
CREATE OR REPLACE VIEW src.v_property_list
AS SELECT pl.property_id,
    il.title,
    c.number_consignment,
    c.receipt_date,
    'IZp-'::text || pl.inventory_number AS inventory_number,
    COALESCE(el.full_name, 'n/d'::character varying) AS full_name,
        CASE
            WHEN pl.state = 1 THEN 'Незакреплено за сотрудником(свободно)'::text
            WHEN pl.state = 2 THEN 'Закреплено за сотрудником'::text
            WHEN pl.state = 3 THEN 'В ремонте'::text
            WHEN pl.state = 4 THEN 'Списано'::text
            ELSE 'n/d state'::text
        END AS state
   FROM src.property_list pl
     JOIN src.items_list il ON pl.items_id = il.items_id
     JOIN src.consignment c ON c.consignment_id = pl.consignment_id
     LEFT JOIN src.employees_list el ON el.employee_id = pl.employee_owner;

COMMENT ON VIEW src.v_property_list IS 'v_property_list - представление, позволяющее просмотреть список имущества компании в удобном виде';

-- Permissions
ALTER TABLE src.v_property_list OWNER TO postgres;
GRANT ALL ON TABLE src.v_property_list TO postgres;
GRANT INSERT, SELECT, UPDATE ON TABLE src.v_property_list TO users;


-- src.v_statistic source
CREATE OR REPLACE VIEW src.v_statistic
AS WITH free_part AS (
         SELECT v.title AS equp,
            count(*) AS cnt
           FROM src.v_property_list v
          WHERE v.state ~~ 'Незакреплено за сотрудником(свободно)'::text
          GROUP BY v.title
          ORDER BY v.title
        ), total AS (
         SELECT v.title AS equp,
            count(*) AS total_cnt
           FROM src.v_property_list v
          GROUP BY v.title
          ORDER BY v.title
        )
 SELECT t.equp,
    t.total_cnt,
    COALESCE(fp.cnt, 0::bigint) AS free_cnt,
    t.total_cnt - COALESCE(fp.cnt, 0::bigint) AS busy_cnt
   FROM total t
     LEFT JOIN free_part fp ON t.equp::text = fp.equp::text;

COMMENT ON VIEW src.v_statistic IS 'v_statistic - статистика по оборудованию. total_cnt - кол-во оборудования всего; free_cnt - кол-во незанятого оборудования; busy_cnt - кол-во занятого оборудования';

-- Permissions
ALTER TABLE src.v_statistic OWNER TO postgres;
GRANT ALL ON TABLE src.v_statistic TO postgres;
GRANT INSERT, SELECT, UPDATE ON TABLE src.v_statistic TO users;


CREATE OR REPLACE FUNCTION src.give_equipment(_employee_id bigint, _property_id bigint[])
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
declare
p_res jsonb;
p_check jsonb;
p_employee_name varchar;
p_property_title jsonb;

begin 
	
	--Проверка на корректный ID сотрудника
	select full_name into p_employee_name
		from src.employees_list as el 
	where el.employee_id = _employee_id;
	if not found then 
		raise exception 'Некорректный ID сотрудника';
	end if;

	--Проверка на корректные ID имущества
	with s as (
		select unnest(_property_id) as i
	)
	, test as (
		select * from src.property_list as pl
			right join s on s.i = pl.property_id
	)
	select jsonb_agg(i) into p_check
		from test 
	where property_id is null;
	if p_check is not null then
		raise exception 'Несуществующий ID ->> %', p_check
		using hint = 'Проверьте введенный массив _property_id';
	end if;

	--Проверка на возможность записать оборудование на сотрудника
	if exists (
		with s as (
			select unnest(_property_id) as i
		)
		select pl.*, s.*
			from src.property_list as pl
			join s on s.i = pl.property_id
		where pl.state in (2,3,4)
		)
	then 
		raise exception 'Попытка закрепить недоступное оборудование'
			using hint = 'Убедитесь, что оборудование не занято, не списано и не находится в ремонте (state)';
	end if;

	--Закрепление имущества за сотрудником
	update src.property_list as pl
		set employee_owner = _employee_id,
			state = 2
	where pl.property_id = any (_property_id);

	select jsonb_agg(title) into p_property_title
		from src.v_property_list vpl 
	where vpl.property_id = any (_property_id);

	p_res = jsonb_build_object('Закреплено за сотрудником', p_employee_name, 'Оборудование', p_property_title);
	return p_res;

end;
$function$
;
COMMENT ON FUNCTION src.give_equipment(int8, _int8) IS 'give_equipment - функция, позволяющая закрепить за сотрудником имущество. На вход принимается ID сотрудника и массив IDs имущества';

-- Permissions
ALTER FUNCTION src.give_equipment(int8, _int8) OWNER TO postgres;
GRANT ALL ON FUNCTION src.give_equipment(int8, _int8) TO public;
GRANT ALL ON FUNCTION src.give_equipment(int8, _int8) TO postgres;
GRANT ALL ON FUNCTION src.give_equipment(int8, _int8) TO users;


CREATE OR REPLACE FUNCTION src.take_equipment(_employee_id bigint, _property_id bigint[])
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
declare
p_res jsonb;
p_employee_name varchar;
p_property_title jsonb;
p_check jsonb;

begin 
	
	--Проверка на корректный ID сотрудника
	select full_name into p_employee_name
		from src.employees_list as el 
	where el.employee_id = _employee_id;
	if not found then 
		raise exception 'Некорректный ID сотрудника';
	end if;

	--Проверка на корректные ID имущества
	with s as (
		select unnest(_property_id) as i
	)
	, test as (
		select * from src.property_list as pl
			right join s on s.i = pl.property_id
	)
	select jsonb_agg(i) into p_check
		from test 
	where property_id is null;
	if p_check is not null then
		raise exception 'Несуществующий ID ->> %', p_check
		using hint = 'Проверьте введенный массив _property_id';
	end if;
	
	with upd as (
		update src.property_list as pl
			set employee_owner = null,
				state = 1
		where pl.property_id = any (_property_id) and pl.employee_owner = _employee_id
		returning property_id
	)
	select jsonb_agg(title) into p_property_title
		from src.v_property_list vpl
		join upd on upd.property_id = vpl.property_id;

	if p_property_title is null then
		raise exception 'Попытка открепить от сотрудника оборудование, которое за ним не было закреплено';
	end if;
	
	p_res = jsonb_build_object('Откреплено от сотрудника', p_employee_name, 'Оборудование', p_property_title);
	return p_res;

end;
$function$
;
COMMENT ON FUNCTION src.take_equipment(int8, _int8) IS 'take_equipment - функция по откреплению имущества от сотрудника';

-- Permissions
ALTER FUNCTION src.take_equipment(int8, _int8) OWNER TO postgres;
GRANT ALL ON FUNCTION src.take_equipment(int8, _int8) TO public;
GRANT ALL ON FUNCTION src.take_equipment(int8, _int8) TO postgres;
GRANT ALL ON FUNCTION src.take_equipment(int8, _int8) TO users;


insert into src.items_list (title) values
('Сетевой фильтр FinePower Standart 418W (4 розетки)'),
('Сетевой фильтр FinePower Standart 618W (6 розеток)'),
('ПК (Intel i5-9400)'),
('ПК (Intel i3-10100F)'),
('Монитор Loc'),
('Монитор LG'),
('Комплект Мышка+Клавиатура Logitech'),
('Ноутбук Apple MacBook M1'),
('Ноутбук HP 15s');

insert into src.employees_list (full_name, department) values
('Васильев Е.Д.', 'Web-Front-DEV'),
('Ким О.А.', 'Web-Front-DEV'),
('Скворцов С.В.', 'Web-Front-DEV'),
('Попов С.М.', 'Web-Back-DEV'),
('Зимин В.В.', 'Web-Back-DEV'),
('Титов В.А.', 'Web-Back-DEV'),
('Игитов М.А.', 'Andriod-DEV'),
('Андрейчуков Г.Э.', 'Andriod-DEV'),
('Сулейманов А.Т.', 'iOS-DEV'),
('Столыпин Н.Н.', 'iOS-DEV'),
('Алферова М.С.', 'Design'),
('Никитина Е.А.', 'Design');

insert into src.consignment (number_consignment, receipt_date) values
('IZ-456/I', '2022-05-26'),
('IZ-584/I', '2022-05-27'),
('IZ-796/II', '2022-06-01');

insert into src.property_list (items_id, consignment_id, employee_owner, state) values
(1, 1, null, 1),(1, 1, null, 1),(1, 1, null, 1),
(2, 1, null, 1),(2, 1, null, 1),(2, 1, null, 1),(2, 1, null, 1),
(8, 1, null, 1),(8, 1, null, 1),
(9, 1, null, 1),(9, 1, null, 1);

insert into src.property_list (items_id, consignment_id, employee_owner, state) values
(3, 2, null, 1),(3, 2, null, 1),(3, 2, null, 1),(3, 2, null, 1),
(4, 2, null, 1),(4, 2, null, 1),(4, 2, null, 1),(4, 2, null, 1),
(5, 2, null, 1),(5, 2, null, 1),(5, 2, null, 1),(5, 2, null, 1),(5, 2, null, 1),(5, 2, null, 1),(5, 2, null, 1),(5, 2, null, 1),
(6, 2, null, 1),(6, 2, null, 1),(6, 2, null, 1),(6, 2, null, 1),
(7, 2, null, 1),(7, 2, null, 1),(7, 2, null, 1),(7, 2, null, 1),(7, 2, null, 1),(7, 2, null, 1),(7, 2, null, 1),(7, 2, null, 1),(7, 2, null, 1),(7, 2, null, 1);
