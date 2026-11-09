import { Entity, PrimaryColumn, Column, Index, DeleteDateColumn } from 'typeorm';
import { ISession } from 'connect-typeorm';

@Entity('sessions')
export class Session implements ISession {
  @PrimaryColumn('varchar', { length: 255 })
  id!: string;

  @Index()
  @Column('bigint')
  expiredAt!: number;

  @Column('text')
  json!: string;

  // connect-typeorm looks this up as `destroyedAt`. The column keeps its existing name.
  @DeleteDateColumn({ name: 'deletedAt', nullable: true })
  destroyedAt?: Date;
}