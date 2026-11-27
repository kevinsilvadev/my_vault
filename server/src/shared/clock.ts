/** Relógio injetável, para testes determinísticos. */
export type Clock = () => Date;

export const systemClock: Clock = () => new Date();
